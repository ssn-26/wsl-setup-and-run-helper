# ==============================================================================
# WSL Control Panel - the window
# A Windows (WPF) window for WSL2: list / open / close / delete / download
# distros, saved accounts (passwords encrypted with Windows DPAPI), XFCE
# desktops (xrdp + Remote Desktop, or Win-KeX on Kali), backup / restore, disk
# compaction, .wslconfig limits.
#
# Start it with "WSL Control Panel.exe" (built by install.ps1) or the
# WSL-Control-Panel.bat launcher. All the work is done by
# Engine.ps1 (dot-sourced below); this file is only the window. Long jobs run
# in a background runspace that loads the same engine, so the window never
# freezes. -Validate builds the window without showing it (used by CI).
#
# Keep this file plain ASCII: Windows PowerShell 5.1 reads a BOM-less script as
# ANSI, so any fancy character could break parsing.
# ==============================================================================

#Requires -Version 5.1
[CmdletBinding()]
param([switch]$Validate)

$ErrorActionPreference = 'Stop'

# Shown in the window, so a bug report can say which version it was.
# Raise it with each change you share.
$PANEL_VERSION = '2.2.0'

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

# The launcher hides the console, so an error that reaches the top is shown in
# a message box (and printed, for -Validate in CI) instead of vanishing.
trap {
    if (-not $Validate) {
        [void][Windows.MessageBox]::Show("The WSL Control Panel hit an unexpected error:`n`n$($_.Exception.Message)`n`n$($_.ScriptStackTrace)", 'WSL Control Panel')
    }
    Write-Error $_ -ErrorAction Continue
    exit 1
}

$ENGINE = Join-Path $PSScriptRoot 'Engine.ps1'
. $ENGINE
. (Join-Path $PSScriptRoot 'AppIcon.ps1')

# ------------------------------------------------------------------------------
# The window: every x:Name in the XAML becomes $ui.<Name>
# ------------------------------------------------------------------------------
$xamlText = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'ui\MainWindow.xaml') -Raw -Encoding UTF8
$win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$xamlText)))
$ui = @{}
foreach ($m in [regex]::Matches($xamlText, 'x:Name="([A-Za-z0-9_]+)"')) {
    $el = $win.FindName($m.Groups[1].Value)
    if ($el) { $ui[$m.Groups[1].Value] = $el }
}
$ui.VersionText.Text = "v$PANEL_VERSION"
$ui.TitleVersion.Text = "v$PANEL_VERSION"
$MIDDOT = [string][char]0x00B7

# ------------------------------------------------------------------------------
# Themes: the Windows 11 colour roles (as in WinUI) in dark and light, plus the
# user's own Windows accent colour. Mica (Windows 11) shows through WindowBg /
# Sidebar when it is available.
# ------------------------------------------------------------------------------
$Themes = @{
    Dark  = @{ WindowBg = '#202020'; Sidebar = '#00000000'; LayerFill = '#4C3A3A3A'; Card = '#0DFFFFFF'; Line = '#1F000000'
               ControlFill = '#0FFFFFFF'; ControlHover = '#15FFFFFF'; ControlPressed = '#08FFFFFF'; ControlStroke = '#12FFFFFF'
               InputActive = '#B31E1E1E'; SubtleHover = '#0FFFFFFF'; SubtleSelected = '#0BFFFFFF'; Raised = '#0FFFFFFF'
               Text = '#FFFFFF'; Muted = '#C5FFFFFF'; Tertiary = '#87FFFFFF'
               Ok = '#6CCB5F'; OkSoft = '#393D1B'; Warn = '#FCE100'; WarnSoft = '#433519'
               Danger = '#FF99A4'; DangerSoft = '#442726'; DangerFill = '#C42B1C'
               Smoke = '#4D000000'; DialogBg = '#2B2B2B'; DialogFooterBg = '#202020'; LogBg = '#0C0C0C' }
    Light = @{ WindowBg = '#F3F3F3'; Sidebar = '#00000000'; LayerFill = '#80FFFFFF'; Card = '#B3FFFFFF'; Line = '#0F000000'
               ControlFill = '#B3FFFFFF'; ControlHover = '#80F9F9F9'; ControlPressed = '#4DF9F9F9'; ControlStroke = '#1F000000'
               InputActive = '#FFFFFF'; SubtleHover = '#09000000'; SubtleSelected = '#06000000'; Raised = '#0A000000'
               Text = '#E4000000'; Muted = '#9E000000'; Tertiary = '#72000000'
               Ok = '#0F7B0F'; OkSoft = '#DFF6DD'; Warn = '#9D5D00'; WarnSoft = '#FFF4CE'
               Danger = '#C42B1C'; DangerSoft = '#FDE7E9'; DangerFill = '#C42B1C'
               Smoke = '#4D000000'; DialogBg = '#FFFFFF'; DialogFooterBg = '#F3F3F3'; LogBg = '#0C0C0C' }
}
# The [Brush] cast matters: without it PowerShell stores its PSObject wrapper
# in the resource dictionary, and WPF rejects that as a colour.
$BrushConv = New-Object Windows.Media.BrushConverter
function New-Brush([string]$hex) { return [Windows.Media.Brush]$BrushConv.ConvertFromString($hex) }

# Windows' own "app mode" setting (Settings > Personalization > Colors).
function Get-WindowsTheme {
    try {
        $v = Get-ItemPropertyValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name AppsUseLightTheme -ErrorAction Stop
        if ($v -eq 1) { return 'Light' }
    } catch { }
    return 'Dark'
}

# (Get-WindowsAccent, the accent colour chosen in Windows, is in AppIcon.ps1.)

# Mixes two '#RRGGBB' colours: $t = 0 gives $a, 1 gives $b.
function Get-MixedColor([string]$a, [string]$b, [double]$t) {
    $out = '#'
    foreach ($i in 1, 3, 5) {
        $x = [Convert]::ToInt32($a.Substring($i, 2), 16); $y = [Convert]::ToInt32($b.Substring($i, 2), 16)
        $out += '{0:X2}' -f [int][math]::Round($x + ($y - $x) * $t)
    }
    return $out
}

# The accent roles, like Windows derives them: a lighter tint in dark mode
# (with black text on it), a darker shade in light mode (with white text).
function Get-AccentRoles([string]$name) {
    $acc = Get-WindowsAccent
    if ($name -eq 'Dark') {
        return @{ Accent = (Get-MixedColor $acc '#FFFFFF' 0.45); AccentHover = (Get-MixedColor $acc '#FFFFFF' 0.35)
                  AccentInk = '#000000'; AccentSoft = '#33' + $acc.Substring(1) }
    }
    return @{ Accent = (Get-MixedColor $acc '#000000' 0.15); AccentHover = (Get-MixedColor $acc '#000000' 0.05)
              AccentInk = '#FFFFFF'; AccentSoft = '#26' + $acc.Substring(1) }
}

# ------------------------------------------------------------------------------
# Windows 11 window material: Mica behind the window and a title bar that
# matches the theme, through dwmapi (compiled by .NET itself - nothing to
# install). On Windows 10 the calls fail quietly and the plain colours stay.
# ------------------------------------------------------------------------------
if (-not ('WslPanel.Win32' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace WslPanel {
    public static class Win32 {
        [StructLayout(LayoutKind.Sequential)]
        public struct MARGINS { public int Left; public int Right; public int Top; public int Bottom; }
        [DllImport("dwmapi.dll")]
        public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);
        [DllImport("dwmapi.dll")]
        public static extern int DwmExtendFrameIntoClientArea(IntPtr hwnd, ref MARGINS margins);
        [DllImport("user32.dll")]
        public static extern int GetSystemMetrics(int index);
    }
}
'@
}
$DWMWA_USE_IMMERSIVE_DARK_MODE = 20
$DWMWA_SYSTEMBACKDROP_TYPE = 38
$script:Mica = $false
$script:Hwnd = [IntPtr]::Zero

function Set-TitleBarTheme {
    if ($script:Hwnd -eq [IntPtr]::Zero) { return }
    $dark = [int]($script:Theme -eq 'Dark')
    try { [void][WslPanel.Win32]::DwmSetWindowAttribute($script:Hwnd, $DWMWA_USE_IMMERSIVE_DARK_MODE, [ref]$dark, 4) } catch { }
}

# Turns on Mica (Windows 11 22H2 and later). $true when it is on.
function Enable-Mica {
    try {
        $script:Hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($win)).EnsureHandle()
        Set-TitleBarTheme
        $mica = 2   # DWMSBT_MAINWINDOW
        if ([WslPanel.Win32]::DwmSetWindowAttribute($script:Hwnd, $DWMWA_SYSTEMBACKDROP_TYPE, [ref]$mica, 4) -ne 0) { return $false }
        $m = New-Object WslPanel.Win32+MARGINS
        $m.Left = -1; $m.Right = -1; $m.Top = -1; $m.Bottom = -1
        [void][WslPanel.Win32]::DwmExtendFrameIntoClientArea($script:Hwnd, [ref]$m)
        [System.Windows.Interop.HwndSource]::FromHwnd($script:Hwnd).CompositionTarget.BackgroundColor = [Windows.Media.Colors]::Transparent
        return $true
    } catch { return $false }
}

# With Mica on, the window draws its own title area like Settings: the app
# name sits in the Mica, and Windows still draws the caption buttons, the
# snap layouts menu and the resize border.
$script:Chrome = $false
function Enable-TitleBar {
    try {
        $c = New-Object System.Windows.Shell.WindowChrome
        $c.CaptionHeight = 40
        $c.GlassFrameThickness = New-Object Windows.Thickness -ArgumentList (-1)
        $c.ResizeBorderThickness = [Windows.SystemParameters]::WindowResizeBorderThickness
        $c.UseAeroCaptionButtons = $true
        $c.CornerRadius = New-Object Windows.CornerRadius 0
        [System.Windows.Shell.WindowChrome]::SetWindowChrome($win, $c)
        $ui.TitleBar.Visibility = 'Visible'
        $ui.NavTitle.Visibility = 'Collapsed'
        return $true
    } catch { return $false }
}
# A maximised window reaches past the screen edges by its (invisible) frame;
# move the content in by that much so nothing is cut off.
function Update-MaximizedMargin {
    if (-not $script:Chrome) { return }
    if ($win.WindowState -ne 'Maximized') { $ui.RootGrid.Margin = New-Object Windows.Thickness 0; return }
    $px = 8
    try { $px = [WslPanel.Win32]::GetSystemMetrics(32) + [WslPanel.Win32]::GetSystemMetrics(92) } catch { }
    $scale = 1.0
    try { $scale = [Windows.Media.VisualTreeHelper]::GetDpi($win).DpiScaleX } catch { }
    $ui.RootGrid.Margin = New-Object Windows.Thickness ($px / $scale)
}
$win.Add_StateChanged({ Update-MaximizedMargin })

$script:Theme = 'Dark'
function Set-Theme([string]$name) {
    $script:Theme = $name
    $roles = $Themes[$name].Clone()
    $accent = Get-AccentRoles $name
    foreach ($k in $accent.Keys) { $roles[$k] = $accent[$k] }
    if ($script:Mica) { $roles.WindowBg = '#00000000' }   # let Mica show through
    foreach ($k in $roles.Keys) { $win.Resources[$k] = [Windows.Media.Brush](New-Brush $roles[$k]) }
    $ui.ThemeText.Text = $(if ($name -eq 'Dark') { 'Light theme' } else { 'Dark theme' })
    Set-TitleBarTheme
}

# ------------------------------------------------------------------------------
# Motion, with the timings of Windows 11 (WinUI): short and easing out. Off
# when Windows' "Animation effects" setting is off.
# ------------------------------------------------------------------------------
$script:Motion = [bool][Windows.SystemParameters]::ClientAreaAnimation
$EaseOut = New-Object Windows.Media.Animation.CubicEase
$EaseOut.EasingMode = 'EaseOut'
$EaseOut.Freeze()

# Animates $prop of $target from $from to $to in $ms milliseconds (or jumps
# straight to the end without motion).
function Start-Motion($target, $prop, [double]$from, [double]$to, [int]$ms) {
    if (-not $script:Motion) { $target.BeginAnimation($prop, $null); $target.SetValue($prop, $to); return }
    $a = New-Object Windows.Media.Animation.DoubleAnimation -ArgumentList $from, $to, (New-Object Windows.Duration ([TimeSpan]::FromMilliseconds($ms)))
    $a.EasingFunction = $EaseOut
    $target.BeginAnimation($prop, $a)
}
$OPACITY = [Windows.UIElement]::OpacityProperty

# The distro page slides up a little and fades in when you pick a distro.
function Start-PageEntrance {
    Start-Motion $ui.PageBody $OPACITY 0 1 250
    Start-Motion $ui.PageShift ([Windows.Media.TranslateTransform]::YProperty) 16 0 300
}

# ------------------------------------------------------------------------------
# Toast (quick results) and dialogs
# ------------------------------------------------------------------------------
$script:ToastTimer = New-Object Windows.Threading.DispatcherTimer
$script:ToastTimer.Interval = [TimeSpan]::FromSeconds(8)
$script:ToastTimer.Add_Tick({ $ui.Toast.Visibility = 'Collapsed'; $script:ToastTimer.Stop() })

# A quick result as a Fluent InfoBar at the top of the page.
# $kind: 'Ok' (success), 'Warn' or 'Error'.
function Show-Toast([string]$msg, [string]$kind = 'Ok') {
    $ui.ToastText.Text = $msg
    switch ($kind) {
        'Warn' {
            $ui.Toast.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'WarnSoft')
            $ui.ToastIconBg.Visibility = 'Collapsed'
            $ui.ToastIcon.Text = [string][char]0xE7BA; $ui.ToastIcon.FontSize = 16
            $ui.ToastIcon.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'Warn')
        }
        default {
            $soft = $(if ($kind -eq 'Error') { 'DangerSoft' } else { 'OkSoft' })
            $strong = $(if ($kind -eq 'Error') { 'Danger' } else { 'Ok' })
            $ui.Toast.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, $soft)
            $ui.ToastIconBg.Visibility = 'Visible'
            $ui.ToastIconBg.SetResourceReference([Windows.Shapes.Shape]::FillProperty, $strong)
            $ui.ToastIcon.Text = $(if ($kind -eq 'Error') { [string][char]0xE711 } else { [string][char]0xE73E })
            $ui.ToastIcon.FontSize = 10
            $ui.ToastIcon.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'AccentInk')
        }
    }
    $ui.Toast.Visibility = 'Visible'
    Start-Motion $ui.Toast $OPACITY 0 1 200
    Start-Motion $ui.ToastShift ([Windows.Media.TranslateTransform]::YProperty) -12 0 250
    $script:ToastTimer.Stop(); $script:ToastTimer.Start()
}
$ui.ToastClose.Add_Click({ $ui.Toast.Visibility = 'Collapsed'; $script:ToastTimer.Stop() })

$Panels = 'PanelMessage', 'PanelUser', 'PanelTask', 'PanelDelete', 'PanelPick', 'PanelDownload', 'PanelBackup',
          'PanelRestore', 'PanelLimits', 'PanelFolders'
# The main button of each dialog, pressed by Enter.
$DefaultButtons = @{ PanelMessage = 'MsgB1'; PanelUser = 'BtnUserOk'; PanelDelete = 'BtnDelOk'; PanelPick = 'PickB1'
                     PanelDownload = 'BtnDlOk'; PanelBackup = 'BtnBakOk'; PanelRestore = 'BtnResOk'; PanelFolders = 'BtnFolClose' }
$script:OpenPanel = ''
$script:ClosedAt = [datetime]::MinValue
function Open-Panel([string]$name, [int]$width = 520) {
    foreach ($p in $Panels) { $ui[$p].Visibility = 'Collapsed' }
    $ui[$name].Visibility = 'Visible'
    $ui.DialogCard.Width = $width
    $script:OpenPanel = $name
    $wasOpen = ($ui.Overlay.Visibility -eq 'Visible')
    $ui.Overlay.Visibility = 'Visible'
    # Like a ContentDialog: the dimmed layer fades in and the dialog settles
    # from slightly larger. One dialog straight after another only swaps.
    if (-not $wasOpen -and ([datetime]::Now - $script:ClosedAt).TotalMilliseconds -gt 150) {
        Start-Motion $ui.Overlay $OPACITY 0 1 167
        Start-Motion $ui.DialogScale ([Windows.Media.ScaleTransform]::ScaleXProperty) 1.05 1 250
        Start-Motion $ui.DialogScale ([Windows.Media.ScaleTransform]::ScaleYProperty) 1.05 1 250
    }
    Start-Motion $ui.DialogCard $OPACITY 0 1 167
}
function Close-Dialog {
    $ui.Overlay.Visibility = 'Collapsed'
    $script:OpenPanel = ''
    $script:ClosedAt = [datetime]::Now
}

# A message with up to three buttons. Each button is @{ Text; Style; Do }:
# Style is 'Primary', 'Btn' or 'DangerBtn'; Do is a scriptblock run after the
# dialog closes. The first button is the main one (rightmost). Do-blocks only
# use $script: variables and functions - they are not closures.
$script:MsgButtons = @()
function Show-Message([string]$title, [string]$text, $buttons) {
    $script:MsgButtons = @($buttons)
    $ui.MsgTitle.Text = $title
    $ui.MsgText.Text = $text
    $slots = @($ui.MsgB1, $ui.MsgB2, $ui.MsgB3)
    for ($i = 0; $i -lt 3; $i++) {
        if ($i -lt $script:MsgButtons.Count) {
            $b = $script:MsgButtons[$i]
            $slots[$i].Content = $b.Text
            $style = $(if ($b.Style) { $b.Style } elseif ($i -eq 0) { 'Primary' } else { 'Btn' })
            $slots[$i].Style = $win.FindResource($style)
            $slots[$i].Visibility = 'Visible'
        } else {
            $slots[$i].Visibility = 'Collapsed'
        }
    }
    Open-Panel 'PanelMessage' 560
}
function Invoke-MsgButton([int]$i) {
    $b = $script:MsgButtons[$i]
    Close-Dialog
    if ($b -and $b.Do) { & $b.Do }
}
# Presses a button from code (keyboard shortcuts), as a click would.
function Invoke-Button($b) {
    if ($b -and $b.IsEnabled -and $b.IsVisible) { $b.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Primitives.ButtonBase]::ClickEvent))) }
}
function Show-Info([string]$title, [string]$text) { Show-Message $title $text @(@{ Text = 'OK' }) }

# A failure, with the end of the last task's output so the reason is visible.
function Show-Failure([string]$title, [string]$text) {
    $tail = @($script:LastLog | Select-Object -Last 12)
    if ($tail.Count) { $text += "`n`nThe last lines of the output:`n" + ($tail -join "`n") }
    Show-Message $title $text @(@{ Text = 'OK' })
}

# Shows a file (selected) or a folder in File Explorer.
function Open-InExplorer([string]$path) {
    if ($path -and (Test-Path -LiteralPath $path -PathType Leaf)) { Start-Process explorer.exe -ArgumentList "/select,""$path""" }
    elseif ($path -and (Test-Path -LiteralPath $path)) { Start-Process explorer.exe -ArgumentList """$path""" }
    else { Show-Toast "That folder does not exist (any more): $path" 'Warn' }
}
$NO_FOLDER = 'No folder chosen yet'

# Windows' folder / file pickers. $null when cancelled.
function Select-Folder([string]$description, [string]$start) {
    $d = New-Object System.Windows.Forms.FolderBrowserDialog
    $d.Description = $description
    if ($start -and (Test-Path -LiteralPath $start)) { $d.SelectedPath = $start }
    if ($d.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $d.SelectedPath }
    return $null
}

# ------------------------------------------------------------------------------
# Background tasks: one runspace with the engine loaded, one task at a time.
# The task's output lines arrive through a queue that a timer moves into the
# progress dialog; when the task ends, its last output is handed to $done.
# ------------------------------------------------------------------------------
$script:Rs = $null
function Initialize-Worker {
    $script:Rs = [runspacefactory]::CreateRunspace()
    $script:Rs.Open()
    $script:Rs.SessionStateProxy.SetVariable('EnginePath', $ENGINE)
    $ps = [powershell]::Create()
    $ps.Runspace = $script:Rs
    [void]$ps.AddScript('. $EnginePath; $ErrorActionPreference = ''Stop''')
    [void]$ps.Invoke()
    if ($ps.Streams.Error.Count) { throw $ps.Streams.Error[0].Exception }
    $ps.Dispose()
}

$script:TaskPs = $null; $script:TaskHandle = $null; $script:TaskDone = $null
$script:LastLog = New-Object System.Collections.Generic.List[string]
$script:TaskTimer = New-Object Windows.Threading.DispatcherTimer
$script:TaskTimer.Interval = [TimeSpan]::FromMilliseconds(200)

# Runs $work (a scriptblock that may use $A) in the background, showing $title
# and the live output, then calls & $done <result>.
function Start-Task([string]$title, [scriptblock]$work, [hashtable]$A, [scriptblock]$done) {
    if ($script:TaskHandle) { return }
    $script:Sync = @{ Lines = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]' }
    $script:TaskDone = $done
    $script:LastLog.Clear()
    $script:Rs.SessionStateProxy.SetVariable('TaskSync', $script:Sync)
    $script:Rs.SessionStateProxy.SetVariable('A', $A)
    $ps = [powershell]::Create()
    $ps.Runspace = $script:Rs
    # Settings may have changed in the window since the last task.
    [void]$ps.AddScript("`$Global:Config = Get-Config`n" + $work.ToString())
    $script:TaskPs = $ps
    $ui.TaskTitle.Text = $title
    $ui.TaskStep.Text = 'Starting...'
    $ui.TaskLog.Text = ''
    $ui.TaskBar.Value = 0
    $script:TaskStart = Get-Date
    Open-Panel 'PanelTask' 680
    $script:TaskHandle = $ps.BeginInvoke()
    $script:TaskTimer.Start()
}

function Read-TaskLines {
    $l = $null; $last = $null
    while ($script:Sync.Lines.TryDequeue([ref]$l)) {
        $ui.TaskLog.AppendText($l + "`r`n")
        $script:LastLog.Add($l)
        $last = $l
    }
    if ($last) { $ui.TaskLog.ScrollToEnd(); $ui.TaskStep.Text = $last.Trim() }
}

$script:TaskTimer.Add_Tick({
    Read-TaskLines
    $ui.TaskBar.Value = ($ui.TaskBar.Value + 2) % 100
    $ui.TaskTime.Text = '{0:m\:ss}' -f ((Get-Date) - $script:TaskStart)
    if (-not $script:TaskHandle.IsCompleted) { return }

    $script:TaskTimer.Stop()
    Read-TaskLines
    $result = $null; $err = $null
    try {
        $out = $script:TaskPs.EndInvoke($script:TaskHandle)
        if ($out.Count) { $result = $out[$out.Count - 1] }
        if ($result -is [psobject]) { $result = $result.PSObject.BaseObject }
    } catch {
        $err = $_.Exception
        if ($err.InnerException) { $err = $err.InnerException }
    }
    $script:TaskPs.Dispose()
    $script:TaskHandle = $null
    $script:Rs.SessionStateProxy.SetVariable('A', $null)   # drops any password it carried
    Close-Dialog
    if ($err) {
        Show-Failure 'Something went wrong' $err.Message
    } elseif ($script:TaskDone) {
        & $script:TaskDone $result
    }
})

# ------------------------------------------------------------------------------
# Distro list and the distro page
# ------------------------------------------------------------------------------
$script:Distros = @()

function Update-DistroList {
    $all = @(Get-WslDistros)
    $script:Distros = @($all | Where-Object { -not $_.IsSystem })
    $hidden = @($all | Where-Object { $_.IsSystem })
    $okHex = $Themes[$script:Theme].Ok; $mutedHex = $Themes[$script:Theme].Muted
    $items = @(foreach ($d in $script:Distros) {
        $meta = '{0} {1} WSL{2} {1} {3:N1} GB' -f $d.State, $MIDDOT, $d.Version, [double](Get-DistroVhdInfo $d.Name).SizeGB
        if ($d.IsDefault) { $meta += " $MIDDOT default" }
        [pscustomobject]@{ Name = $d.Name; Initial = $d.Name.Substring(0, 1).ToUpper(); Meta = $meta
                           Dot = $(if ($d.State -eq 'Running') { $okHex } else { $mutedHex }) }
    })
    $keep = $null
    if ($ui.DistroList.SelectedItem) { $keep = $ui.DistroList.SelectedItem.Name }
    if ($script:SelectNext) { $keep = $script:SelectNext; $script:SelectNext = $null }
    $script:Refreshing = $true   # a refresh re-selects without the page animation
    try {
        $ui.DistroList.ItemsSource = $items
        $pick = @($items | Where-Object { $_.Name -eq $keep }) | Select-Object -First 1
        if ($pick) { $ui.DistroList.SelectedItem = $pick } elseif ($items.Count) { $ui.DistroList.SelectedIndex = 0 }
    } finally { $script:Refreshing = $false }
    $ui.NoDistros.Visibility = $(if ($items.Count) { 'Collapsed' } else { 'Visible' })
    $ui.BtnQuickOpen.IsEnabled = ($items.Count -gt 0)
    if ($hidden.Count) {
        $ui.HiddenNote.Text = "Hidden: $(($hidden | ForEach-Object { $_.Name }) -join ', ') (they belong to Docker / Rancher Desktop)"
        $ui.HiddenNote.Visibility = 'Visible'
    } else { $ui.HiddenNote.Visibility = 'Collapsed' }
    Show-DistroPage
}

function Get-CurrentDistro {
    if (-not $ui.DistroList.SelectedItem) { return $null }
    $n = $ui.DistroList.SelectedItem.Name
    return ($script:Distros | Where-Object { $_.Name -eq $n } | Select-Object -First 1)
}

$OPEN_MYSELF = 'Type my login myself'
function Show-DistroPage {
    $d = Get-CurrentDistro
    if (-not $d) {
        $ui.DistroPage.Visibility = 'Collapsed'; $ui.EmptyPage.Visibility = 'Visible'
        if ($script:Distros.Count) {
            $ui.EmptyTitle.Text = 'Pick a distro'
            $ui.EmptyText.Text = 'Choose one on the left to open it or change its settings.'
            $ui.BtnEmptyDownload.Visibility = 'Collapsed'
        } else {
            $ui.EmptyTitle.Text = 'No Linux distros yet'
            $ui.EmptyText.Text = "Download one from Microsoft's official list - Ubuntu is a good first choice. It takes a few minutes."
            $ui.BtnEmptyDownload.Visibility = 'Visible'
        }
        return
    }
    $ui.DistroPage.Visibility = 'Visible'; $ui.EmptyPage.Visibility = 'Collapsed'
    $running = ($d.State -eq 'Running')
    $ui.HeroInitial.Text = $d.Name.Substring(0, 1).ToUpper()
    $ui.HeroName.Text = $d.Name
    $ui.StateText.Text = $d.State
    $ui.StatePill.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, $(if ($running) { 'OkSoft' } else { 'Raised' }))
    $ui.StateText.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, $(if ($running) { 'Ok' } else { 'Muted' }))
    $ui.StateDot.SetResourceReference([Windows.Shapes.Shape]::FillProperty, $(if ($running) { 'Ok' } else { 'Muted' }))
    $ui.HeroMeta.Text = "WSL $($d.Version)" + $(if ($d.IsDefault) { " $MIDDOT default distro" } else { '' })
    $ui.BtnClose.Visibility = $(if ($running) { 'Visible' } else { 'Collapsed' })
    $vhd = Get-DistroVhdInfo $d.Name
    $ui.StatDisk.Text = ('{0:N1} GB' -f [double]$vhd.SizeGB)
    $script:DiskFile = $(if ($vhd.Exists) { $vhd.VhdxPath } else { $vhd.BasePath })
    $ui.DiskPath.Text = $(if ($vhd.BasePath) { $vhd.BasePath } else { 'Location not found' })
    $ui.DiskPath.ToolTip = $ui.DiskPath.Text
    $port = Get-DistroPort $d.Name
    $ui.StatPort.Text = [string]$port
    $ui.PortBox.Text = [string]$port

    $accounts = @(Get-SavedAccounts $d.Name)
    $ui.AccountList.ItemsSource = @($accounts | ForEach-Object { [pscustomobject]@{ Name = $_.Username; Initial = $_.Username.Substring(0, 1).ToUpper() } })
    $ui.NoUsers.Visibility = $(if ($accounts.Count) { 'Collapsed' } else { 'Visible' })
    # "Open as": the saved logins, or none (you type your login yourself).
    $ui.OpenAsList.ItemsSource = @(@($accounts | ForEach-Object { $_.Username }) + $OPEN_MYSELF)
    $ui.OpenAsList.SelectedIndex = 0
    Update-LiveStatus
}

# ------------------------------------------------------------------------------
# Live status tiles: the distro's disk and the memory of the WSL VM. Only cheap
# reads (a file size, the free space, one process), so a timer can refresh them
# every few seconds without ever calling wsl.exe.
# ------------------------------------------------------------------------------
$script:TotalRamGB = 0
# (Read directly from Windows: a WMI query can take many seconds on a cold start.)
try { Add-Type -AssemblyName Microsoft.VisualBasic; $script:TotalRamGB = [double](New-Object Microsoft.VisualBasic.Devices.ComputerInfo).TotalPhysicalMemory / 1GB } catch { }

# How much memory WSL may use: memory= in .wslconfig, else WSL's default
# (half of the PC's memory). 0 when unknown.
function Get-WslMemoryLimitGB {
    try {
        $path = Get-WslConfigPath
        if (Test-Path -LiteralPath $path) {
            foreach ($line in Get-Content -LiteralPath $path) {
                if ($line -match '^\s*memory\s*=\s*([\d.]+)\s*(GB|MB|G|M)?\s*$') {
                    $n = [double]$Matches[1]
                    if ($Matches[2] -match '^M') { return $n / 1024 }
                    return $n
                }
            }
        }
    } catch { }
    return ($script:TotalRamGB / 2)
}

$script:VmWasUp = $false
function Update-LiveStatus {
    $d = Get-CurrentDistro
    if (-not $d -or $ui.DistroPage.Visibility -ne 'Visible') { return }
    $vhd = Get-DistroVhdInfo $d.Name
    $ui.LiveDisk.Text = '{0:N1} GB' -f [double]$vhd.SizeGB
    $ui.LiveDiskBar.Value = 0
    $ui.LiveDiskNote.Text = 'Its disk file was not found'
    if ($vhd.Exists) {
        try {
            $drive = New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($vhd.VhdxPath))
            $free = $drive.AvailableFreeSpace / 1GB; $total = $drive.TotalSize / 1GB
            $ui.LiveDiskNote.Text = '{0} {1:N0} GB free of {2:N0} GB' -f $drive.Name.TrimEnd('\'), $free, $total
            if ($total -gt 0) { $ui.LiveDiskBar.Value = 100 * ($total - $free) / $total }
        } catch { }
    }

    $vm = @(Get-Process -Name VmmemWSL -ErrorAction SilentlyContinue)
    if ($vm.Count) {
        $used = ($vm | Measure-Object -Property WorkingSet64 -Sum).Sum / 1GB
        $limit = Get-WslMemoryLimitGB
        $ui.LiveMem.Text = '{0:N1} GB' -f $used
        $ui.LiveMemNote.Text = $(if ($limit -gt 0) { 'In use, of the {0:N1} GB WSL may use' -f $limit } else { 'In use' })
        $ui.LiveMemBar.Value = $(if ($limit -gt 0) { [math]::Min(100, 100 * $used / $limit) } else { 0 })
        $script:VmWasUp = $true
    } else {
        $ui.LiveMem.Text = '0 GB'
        $ui.LiveMemNote.Text = 'WSL is not running'
        $ui.LiveMemBar.Value = 0
        # WSL stopped by itself (idle timeout, or closed elsewhere): show that.
        if ($script:VmWasUp) {
            $script:VmWasUp = $false
            if (@($script:Distros | Where-Object { $_.State -eq 'Running' }).Count) { Update-DistroList }
        }
    }
}

$script:LiveTimer = New-Object Windows.Threading.DispatcherTimer
$script:LiveTimer.Interval = [TimeSpan]::FromSeconds(5)
$script:LiveTimer.Add_Tick({ if (-not $script:TaskHandle -and $win.IsActive) { Update-LiveStatus } })

# The saved login chosen under "Open as" ('' = none).
function Get-OpenAsAccount {
    $s = [string]$ui.OpenAsList.SelectedItem
    if (-not $s -or $s -eq $OPEN_MYSELF) { return '' }
    return $s
}

# ------------------------------------------------------------------------------
# Opening a desktop or a terminal. $script:Open holds what is being opened; each
# attempt runs in the background and its Status decides the next question.
# ------------------------------------------------------------------------------
$script:Open = @{}
function Start-Open {
    $o = $script:Open
    $A = @{ Distro = $o.Distro; Account = $o.Account; AfterInstall = [bool]$o.AfterInstall; SkipFirstUser = [bool]$o.SkipFirstUser }
    if ($o.Mode -eq 'Terminal') {
        Start-Task "Opening a terminal for $($o.Distro)" { Test-DistroReady $A.Distro $A.Account } $A { param($r) Complete-Open $r }
    } else {
        Start-Task "Opening the $($o.Distro) desktop" {
            Open-DistroDesktop $A.Distro $A.Account -AfterInstall:$A.AfterInstall -SkipFirstUser:$A.SkipFirstUser
        } $A { param($r) Complete-Open $r }
    }
}

function Complete-Open($r) {
    $o = $script:Open
    $d = $o.Distro
    switch ($r.Status) {
        'Ready' {
            Open-DistroTerminal $d $o.Account
            Update-DistroList
            Show-Toast "Terminal opened for $d."
        }
        'OpenedRdp' {
            Update-DistroList
            if ($r.WithLogin) { Show-Toast "Remote Desktop opened for $d as $($o.Account)." }
            else { Show-Toast 'Remote Desktop opened - log in with your Linux username and password.' 'Warn' }
        }
        'OpenedKex' {
            Update-DistroList
            Show-Info "The Kali desktop (Win-KeX) is starting" ("A console window opened for it:`n" +
                "  - FIRST time only: it asks for a one-time Win-KeX password (local only). Type it twice, then answer ""n"" to the view-only question.`n" +
                "  - Every time after: it just opens the desktop.`n`n" +
                "Closing that console does NOT close the desktop. If nothing appears, read the console window for the error.")
        }
        'StartFailed' { Show-StartFailed $r }
        'UserMissing' {
            Show-Message "The saved account '$($r.Account)' does not exist inside $d" ("(Usually because the distro was deleted and downloaded again - a fresh distro only has ""root"".)`n`n" +
                "The panel can create it again now.") @(
                @{ Text = "Create '$($r.Account)' again"; Do = { Open-UserDialog 'recreate' $script:Open.Distro 'open' $script:Open.Account } },
                @{ Text = 'Cancel' })
        }
        'NeedsFirstUser' { Open-UserDialog 'first' $d 'open' }
        'KexNeedsUser' {
            Show-Message 'The Kali desktop (Win-KeX) cannot run as root' "$d has no normal user as its default login yet. Create your user now, then the desktop opens with it." @(
                @{ Text = 'Create my user'; Do = { Open-UserDialog 'first' $script:Open.Distro 'open' } },
                @{ Text = 'Cancel' })
        }
        'PortConflict' {
            $script:Open.Conflict = $r.Conflict; $script:Open.Port = $r.Port
            Show-Message "Port $($r.Port) is taken" ("'$($r.Conflict)' is running its own desktop on port $($r.Port). WSL distros share one network, so two desktops cannot use the same port.") @(
                @{ Text = "Give $d a different port"; Do = {
                    Start-Task "Finding a free port for $($script:Open.Distro)" { Set-NextFreePort $A.Distro $A.Port } @{ Distro = $script:Open.Distro; Port = $script:Open.Port } {
                        param($np) Show-Toast "$($script:Open.Distro) will use port $np from now on."; Start-Open } } },
                @{ Text = "Close '$($r.Conflict)'"; Style = 'Btn'; Do = {
                    Start-Task "Closing $($script:Open.Conflict)" { Stop-Distro $A.Name } @{ Name = $script:Open.Conflict } { param($x) Start-Open } } },
                @{ Text = 'Cancel' })
        }
        'NeedsInstall' {
            $script:Open.Port = $r.Port; $script:Open.IsKali = [bool]$r.IsKali
            Show-Message "$d has no desktop yet" ("This distro has no desktop server the panel knows how to open. Most distros open via xrdp (Remote Desktop); Kali opens via Win-KeX.`n`n" +
                "The panel can download and install one now (needs internet and a few hundred MB; it can take several minutes - Arch is the slowest, because it builds xrdp).") @(
                @{ Text = 'Install the desktop now'; Do = { Start-DesktopInstall } },
                @{ Text = 'Open a Terminal instead'; Style = 'Btn'; Do = { $script:Open.Mode = 'Terminal'; Start-Open } },
                @{ Text = 'Cancel' })
        }
        'NotReachable' {
            Show-Failure 'The desktop is still not reachable' "The desktop was installed but is still not reachable on port $($r.Port). Open the distro as a Terminal and check the xrdp service, then try again."
        }
        default { Show-Failure 'Could not open it' "Unexpected answer: $($r.Status)" }
    }
}

function Start-DesktopInstall {
    $A = @{ Distro = $script:Open.Distro; Port = $script:Open.Port; IsKali = $script:Open.IsKali }
    Start-Task "Installing a desktop for $($A.Distro)" { Install-DistroDesktop $A.Distro $A.Port $A.IsKali } $A {
        param($r)
        if ($r.Ok) {
            Show-Toast 'Desktop installation finished.'
            $script:Open.AfterInstall = $true
            Start-Open
        } else {
            $msg = "Exit code $($r.ExitCode). Common causes:`n  - no internet connection inside the distro`n  - the package manager is locked by another update running now`n" +
                   "  - out of disk space`n  - Arch: building xrdp from the AUR failed (AUR_BUILD_FAILED)`n  - an unrecognised package manager (UNKNOWN_PKG_MANAGER)"
            if ($r.Log) { $msg += "`n`nThe full output is saved in:`n$($r.Log)" }
            Show-Failure 'The desktop install did not complete' $msg
        }
    }
}

function Show-StartFailed($r) {
    $script:Open.Locked = [bool]$r.Locked
    $text = "WSL says:`n$($r.Error)"
    if ($r.Locked) {
        $text += "`n`nAnother program has its disk file (ext4.vhdx) open, so WSL cannot use it. Usually: WSL got stuck, a copy or backup of that file is still running, " +
                 "the file was double-clicked (Windows mounted it), or antivirus is scanning it."
    }
    $buttons = @(@{ Text = 'Shut down WSL and try again'; Do = { Start-StartRepair 'Shutdown' } })
    if ($r.Locked) { $buttons += @{ Text = 'Detach the disk and try again'; Style = 'Btn'; Do = { Start-StartRepair 'Detach' } } }
    $buttons += @{ Text = 'Cancel' }
    Show-Message "$($script:Open.Distro) could not start" $text $buttons
}

function Start-StartRepair([string]$how) {
    Start-Task "Fixing $($script:Open.Distro)" { Repair-DistroStart $A.Distro $A.How } @{ Distro = $script:Open.Distro; How = $how } {
        param($ok)
        if ($ok) { Start-Open } else { Show-Failure 'Nothing was changed' 'The administrator prompt was declined.' }
    }
}

# ------------------------------------------------------------------------------
# The username + password dialog. Modes:
#   first     a fresh distro's first user (then: 'open' carries on opening,
#             'download' finishes a download)
#   add       save a login, and optionally create the Linux user
#   recreate  create a saved login's missing Linux user, then carry on opening
#   password  change a saved login's password
# ------------------------------------------------------------------------------
$script:UserCtx = @{}
function Open-UserDialog([string]$mode, [string]$distro, [string]$then = '', [string]$fixedName = '') {
    $script:UserCtx = @{ Mode = $mode; Distro = $distro; Then = $then }
    $ui.UName.IsReadOnly = [bool]$fixedName
    $ui.UName.Text = $(if ($fixedName) { $fixedName } else { Get-SuggestedUserName })
    $ui.P1.Password = ''; $ui.P2.Password = ''
    $ui.CreateRow.Visibility = $(if ($mode -eq 'add') { 'Visible' } else { 'Collapsed' })
    $ui.CreateSwitch.IsChecked = $true
    $ui.BtnUserCancel.Content = 'Cancel'
    switch ($mode) {
        'first' {
            $ui.UserTitle.Text = 'Create your Linux user'
            $ui.UserIntro.Text = "$distro has no user of its own yet - only root, which cannot log in to a desktop. This creates yours: a username and " +
                                 "password with admin (sudo) rights, the desktop session set up, and the login saved here (encrypted) for auto-login. " +
                                 "It also becomes the default login, so a Terminal opens as you too."
            $ui.BtnUserOk.Content = 'Create user'
            $ui.BtnUserCancel.Content = 'Not now'
        }
        'add' {
            $ui.UserTitle.Text = "Add an account to $distro"
            $ui.UserIntro.Text = 'Saves a login here for auto-login (the password is encrypted with Windows DPAPI).'
            $ui.BtnUserOk.Content = 'Save account'
        }
        'recreate' {
            $ui.UserTitle.Text = "Create '$fixedName' inside $distro again"
            $ui.UserIntro.Text = 'Makes the Linux user again with admin (sudo) rights and the desktop session, and saves the new password here.'
            $ui.BtnUserOk.Content = 'Create user'
        }
        'password' {
            $ui.UserTitle.Text = "Change the password for '$fixedName'"
            $ui.UserIntro.Text = 'Changes it in Linux AND in the panel.'
            $ui.BtnUserOk.Content = 'Change password'
        }
    }
    Update-UserForm
    Open-Panel 'PanelUser'
    if ($fixedName) { [void]$ui.P1.Focus() } else { [void]$ui.UName.Focus() }
}

function Update-UserForm {
    $mode = $script:UserCtx.Mode
    $create = ($mode -ne 'add' -or $ui.CreateSwitch.IsChecked)
    $ui.P1Label.Text = $(if ($mode -eq 'password') { 'New password' } elseif ($create) { 'Password' } else { 'The EXISTING Linux password' })
    $nameOk = Test-LinuxUserName $ui.UName.Text
    if ($ui.UName.Text -and -not $nameOk) {
        $ui.UHint.Text = 'Use lowercase letters, digits, - and _, starting with a letter (e.g. alex)'
        $ui.UHint.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'Danger')
    } else {
        $ui.UHint.Text = 'Lowercase letters, digits, - and _, starting with a letter'
        $ui.UHint.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'Muted')
    }
    $pwOk = $ui.P1.Password.Length -gt 0 -and $ui.P1.Password -ceq $ui.P2.Password
    if ($ui.P2.Password) {
        $ui.PHint.Text = $(if ($pwOk) { 'The passwords match' } else { 'The two passwords do not match' })
        $ui.PHint.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, $(if ($pwOk) { 'Ok' } else { 'Danger' }))
    } else { $ui.PHint.Text = ' ' }
    $ui.BtnUserOk.IsEnabled = $nameOk -and $pwOk
}

function Submit-UserDialog {
    $c = $script:UserCtx
    $A = @{ Distro = $c.Distro; User = $ui.UName.Text; Password = $ui.P1.Password }
    $ui.P1.Password = ''; $ui.P2.Password = ''
    $script:UserCtx.User = $A.User
    switch ($c.Mode) {
        'first' {
            Start-Task "Creating $($A.User) in $($A.Distro)" { New-FirstUser $A.Distro $A.User $A.Password } $A { param($ok) Complete-UserTask $ok }
        }
        'recreate' {
            Start-Task "Creating $($A.User) in $($A.Distro)" { Add-PanelAccount $A.Distro $A.User $A.Password $true } $A { param($ok) Complete-UserTask $ok }
        }
        'password' {
            Start-Task "Changing the password for $($A.User)" { Set-AccountPassword $A.Distro $A.User $A.Password } $A {
                param($ok)
                if ($ok) { Show-Toast 'Password updated in Linux and in the panel.' }
                else { Show-Failure 'Linux refused the change' "Does '$($script:UserCtx.User)' exist inside $($script:UserCtx.Distro)? Nothing was saved." }
            }
        }
        'add' {
            if ($ui.CreateSwitch.IsChecked) {
                Start-Task "Creating $($A.User) in $($A.Distro)" { Add-PanelAccount $A.Distro $A.User $A.Password $true } $A { param($ok) Complete-UserTask $ok }
            } else {
                # Only remembering a login: nothing to run inside the distro.
                Close-Dialog
                [void](Add-PanelAccount $A.Distro $A.User $A.Password $false)
                Show-DistroPage
                Show-Toast "Account '$($A.User)' saved for $($A.Distro). NOTE: this did NOT create the Linux user - it only remembers the login." 'Warn'
            }
        }
    }
}

function Complete-UserTask($ok) {
    $c = $script:UserCtx
    if (-not $ok) {
        Show-Failure 'The user could not be created' 'Nothing was saved. Open the distro as a Terminal to check it is healthy, then try again.'
        return
    }
    Update-DistroList
    Show-Toast "Account '$($c.User)' saved for $($c.Distro) (encrypted with Windows DPAPI)."
    if ($c.Then -eq 'open') {
        $script:Open.Account = $c.User
        Start-Open
    } elseif ($c.Then -eq 'download') {
        Show-Toast "$($c.Distro) is ready - press Open desktop to start it as '$($c.User)'."
    }
}

function Cancel-UserDialog {
    Close-Dialog
    $c = $script:UserCtx
    if ($c.Mode -eq 'first' -and $c.Then -eq 'open') {
        # Same as the text panel: without a new user, carry on opening as is.
        $script:Open.SkipFirstUser = $true
        Start-Open
    } elseif ($c.Mode -eq 'first' -and $c.Then -eq 'download') {
        Show-Toast "$($c.Distro) is installed - pick it and press Open desktop (it asks for your user then)."
    }
}

# ------------------------------------------------------------------------------
# Distro page actions
# ------------------------------------------------------------------------------
function Start-OpenCurrent([string]$mode) {
    $d = Get-CurrentDistro
    if (-not $d) { return }
    $script:Open = @{ Distro = $d.Name; Account = (Get-OpenAsAccount); Mode = $mode; AfterInstall = $false; SkipFirstUser = $false }
    Start-Open
}

function Show-CompactDialog([string]$distro) {
    $vhd = Get-DistroVhdInfo $distro
    if (-not $vhd.Exists) { Show-Failure 'Nothing to compact' "Could not find ext4.vhdx for $distro."; return }
    $script:CompactDistro = $distro
    Show-Message "Compact the virtual hard disk of $distro" ("Disk file: $($vhd.VhdxPath)`nCurrent size: $($vhd.SizeGB) GB`n`n" +
        "A WSL2 disk grows as files are added but never shrinks when you delete files inside Linux. Compacting hands that unused space back to Windows.`n`n" +
        "This stops ALL WSL distros (wsl --shutdown) and needs administrator rights.") @(
        @{ Text = 'Compact now (recommended)'; Do = { Start-Compact $false } },
        @{ Text = 'Turn on sparse mode'; Style = 'Btn'; Do = { Start-Compact $true } },
        @{ Text = 'Cancel' })
}
function Start-Compact([bool]$sparse) {
    Start-Task "Compacting $($script:CompactDistro)" { Invoke-CompactDisk $A.Distro $A.Sparse } @{ Distro = $script:CompactDistro; Sparse = $sparse } {
        param($r) Update-DistroList; Show-Toast $r.Message $r.Kind
    }
}

$ui.DistroList.Add_SelectionChanged({ Show-DistroPage; if (-not $script:Refreshing) { Start-PageEntrance } })
$ui.BtnEmptyDownload.Add_Click({ Invoke-Button $ui.BtnDownload })
$ui.BtnDesktop.Add_Click({ Start-OpenCurrent 'Desktop' })
$ui.BtnTerminal.Add_Click({ Start-OpenCurrent 'Terminal' })
$ui.BtnQuickOpen.Add_Click({
    # The default distro's desktop with its first saved account.
    $d = $script:Distros | Where-Object { $_.IsDefault } | Select-Object -First 1
    if (-not $d) { $d = $script:Distros | Select-Object -First 1 }
    if (-not $d) { Show-Toast 'No distros installed yet - use Download a distro.' 'Warn'; return }
    $acc = @(Get-SavedAccounts $d.Name) | Select-Object -First 1
    $script:Open = @{ Distro = $d.Name; Account = $(if ($acc) { $acc.Username } else { '' }); Mode = 'Desktop'; AfterInstall = $false; SkipFirstUser = $false }
    Start-Open
})
$ui.BtnClose.Add_Click({
    $d = Get-CurrentDistro
    $script:LastClosed = $d.Name
    Start-Task "Closing $($d.Name)" { Stop-OneDistro $A.Name } @{ Name = $d.Name } { param($x) Update-DistroList; Show-Toast "$($script:LastClosed) is stopped." }
})
$ui.BtnAddUser.Add_Click({ Open-UserDialog 'add' (Get-CurrentDistro).Name })
# The buttons inside each account row (Change password / Remove).
$ui.AccountList.AddHandler([Windows.Controls.Button]::ClickEvent, [Windows.RoutedEventHandler]{
    param($s, $e)
    $b = $e.OriginalSource
    $d = (Get-CurrentDistro).Name
    if ([string]$b.Content -eq 'Remove') {
        Remove-SavedAccount $d ([string]$b.Tag)
        Show-DistroPage
        Show-Toast "Removed saved account '$($b.Tag)' (the Linux user is untouched)."
    } else {
        Open-UserDialog 'password' $d '' ([string]$b.Tag)
    }
})
$ui.BtnPortSave.Add_Click({
    $d = (Get-CurrentDistro).Name
    $np = $ui.PortBox.Text.Trim()
    if (-not ($np -match '^\d{1,5}$' -and [int]$np -ge 1024 -and [int]$np -le 65535)) { Show-Toast "'$np' is not a port between 1024 and 65535." 'Error'; return }
    $problem = Get-PortProblem $d ([int]$np)
    if ($problem) { Show-Toast "$problem Pick another port." 'Error'; return }
    Set-DistroPort $d ([int]$np)
    Show-DistroPage
    Show-Toast "Port set to $np - used the next time you open the desktop."
})
$ui.BtnSystemd.Add_Click({
    $script:SysDistro = (Get-CurrentDistro).Name
    Start-Task "Checking systemd in $($script:SysDistro)" { Get-SystemdEnabled $A.Distro } @{ Distro = $script:SysDistro } {
        param($on)
        $script:SysOn = [bool]$on
        Show-Message "systemd: $($script:SysDistro)" ("systemd is currently: $(if ($on) { 'ENABLED' } else { 'DISABLED' })`n`n" +
            "systemd is the standard Linux service manager. With it on, services (Docker, SSH, cron, databases) start properly. It is set in /etc/wsl.conf and takes effect after the distro restarts (the panel stops it for you).") @(
            @{ Text = $(if ($on) { 'Turn it OFF' } else { 'Turn it ON' }); Do = {
                Start-Task "Changing systemd in $($script:SysDistro)" { Set-SystemdEnabled $A.Distro $A.Enable } @{ Distro = $script:SysDistro; Enable = (-not $script:SysOn) } {
                    param($ok)
                    Update-DistroList
                    if ($ok) { Show-Toast "systemd is $(if ($script:SysOn) { 'off' } else { 'on' }) from the next start ($($script:SysDistro) was stopped to apply it)." }
                    else { Show-Failure 'Could not edit /etc/wsl.conf' 'Nothing was changed.' }
                } } },
            @{ Text = 'Cancel' })
    }
})
$ui.BtnCompact.Add_Click({ Show-CompactDialog (Get-CurrentDistro).Name })
$ui.BtnOpenDiskFolder.Add_Click({ Open-InExplorer $script:DiskFile })
$ui.BtnDelete.Add_Click({
    $d = (Get-CurrentDistro).Name
    $script:DelDistro = $d
    $ui.DelTitle.Text = "Delete $d?"
    $ui.DelLabel.Text = "Type the distro name exactly to confirm ($d)"
    $ui.DelName.Text = ''
    Open-Panel 'PanelDelete'
    [void]$ui.DelName.Focus()
})
$ui.DelName.Add_TextChanged({ $ui.BtnDelOk.IsEnabled = ($ui.DelName.Text -ceq $script:DelDistro) })
$ui.BtnDelCancel.Add_Click({ Close-Dialog; Show-Toast 'Cancelled - nothing was deleted.' 'Warn' })
$ui.BtnDelOk.Add_Click({
    Start-Task "Deleting $($script:DelDistro)" { Remove-WslDistro $A.Name } @{ Name = $script:DelDistro } {
        param($x) Update-DistroList; Show-Toast "$($script:DelDistro) was deleted."
    }
})

# User dialog
$ui.UName.Add_TextChanged({ Update-UserForm })
$ui.P1.Add_PasswordChanged({ Update-UserForm })
$ui.P2.Add_PasswordChanged({ Update-UserForm })
$ui.CreateSwitch.Add_Click({ Update-UserForm })
$ui.BtnUserOk.Add_Click({ Submit-UserDialog })
$ui.BtnUserCancel.Add_Click({ Cancel-UserDialog })

# Message dialog buttons
$ui.MsgB1.Add_Click({ Invoke-MsgButton 0 })
$ui.MsgB2.Add_Click({ Invoke-MsgButton 1 })
$ui.MsgB3.Add_Click({ Invoke-MsgButton 2 })

# ------------------------------------------------------------------------------
# Pick-from-a-list dialog (close a running distro, compact a disk)
# ------------------------------------------------------------------------------
$script:PickDo1 = $null; $script:PickDo3 = $null
function Show-Pick([string]$title, [string]$text, [string[]]$items, [string]$b1, [scriptblock]$do1, [string]$b3 = '', [scriptblock]$do3 = $null) {
    $ui.PickTitle.Text = $title
    $ui.PickText.Text = $text
    $ui.PickList.ItemsSource = $items
    $ui.PickB1.Content = $b1
    $ui.PickB1.IsEnabled = $false
    $script:PickDo1 = $do1; $script:PickDo3 = $do3
    $ui.PickB3.Content = $b3
    $ui.PickB3.Visibility = $(if ($b3) { 'Visible' } else { 'Collapsed' })
    Open-Panel 'PanelPick'
}
$ui.PickList.Add_SelectionChanged({ $ui.PickB1.IsEnabled = ($null -ne $ui.PickList.SelectedItem) })
$ui.PickB1.Add_Click({ $script:Picked = [string]$ui.PickList.SelectedItem; Close-Dialog; & $script:PickDo1 })
$ui.PickB2.Add_Click({ Close-Dialog })
$ui.PickB3.Add_Click({ Close-Dialog; & $script:PickDo3 })

# ------------------------------------------------------------------------------
# Sidebar: download
# ------------------------------------------------------------------------------
$ui.BtnDownload.Add_Click({
    Start-Task "Reading Microsoft's list of distros" { Get-OnlineDistros } @{} {
        param($r)
        $ui.OnlineList.ItemsSource = @($r.Rows)
        $ui.DlName.Text = ''
        $script:DlBase = ''
        Update-DownloadForm
        Open-Panel 'PanelDownload' 580
    }
})
# The folder is never filled in for you: Download stays off until you choose one.
function Update-DownloadForm {
    $name = $ui.DlName.Text.Trim()
    $ui.DlFolder.Text = $(if (-not $script:DlBase) { $NO_FOLDER } elseif ($name) { Join-Path $script:DlBase $name } else { $script:DlBase })
    $ui.BtnDlOk.IsEnabled = [bool]((Test-DistroName $name) -and $script:DlBase)
}
$ui.OnlineList.Add_SelectionChanged({ if ($ui.OnlineList.SelectedItem) { $ui.DlName.Text = $ui.OnlineList.SelectedItem.Name } })
$ui.DlName.Add_TextChanged({ Update-DownloadForm })
$ui.BtnDlFolder.Add_Click({
    $f = Select-Folder 'Where should the new distro be stored? (a folder named after it is created inside)' $Global:Config.WslBase
    if ($f) { $script:DlBase = $f; Update-DownloadForm }
})
$ui.BtnDlCancel.Add_Click({ Close-Dialog })
$ui.BtnDlOk.Add_Click({
    $problem = Set-DataFolder 'WslBase' $script:DlBase   # remembered as the picker's start next time
    if ($problem) { Show-Toast $problem 'Error'; return }
    $script:Dl = @{ Name = $ui.DlName.Text.Trim(); Base = $script:DlBase }
    Start-Task "Downloading $($script:Dl.Name)" { Install-WslDistro $A.Name $A.Base } $script:Dl.Clone() {
        param($r)
        $script:Dl.Location = $r.Location
        if ($r.Ok) { Complete-Download; return }
        Show-Message "The download / install FAILED (exit code $($r.ExitCode))" ("Common causes:`n" +
            "  - the server dropped the connection (""connection was reset""). Debian does this often.`n" +
            "  - the name was typed wrong, or a distro with that name is already installed`n`n" +
            "The RESUMABLE download fetches the same official file in pieces, continues wherever the connection drops, checks its SHA-256 fingerprint, then installs it.") @(
            @{ Text = 'Try the resumable download'; Do = {
                Start-Task "Downloading $($script:Dl.Name) (resumable)" { Install-WslDistroResumable $A.Name $A.Location } $script:Dl.Clone() {
                    param($r2)
                    if ($r2.Ok) { Complete-Download } else { Show-Failure 'The resumable download did not work' $r2.Message }
                } } },
            @{ Text = 'Cancel' })
    }
})

# After a download: most distros start with only root, so offer to create the
# user right away and the new distro is ready to open in one go.
function Complete-Download {
    $script:SelectNext = $script:Dl.Name
    Update-DistroList
    Start-Task "Checking $($script:Dl.Name)" { Test-RootDefault $A.Name } @{ Name = $script:Dl.Name } {
        param($root)
        if ($root) { Open-UserDialog 'first' $script:Dl.Name 'download' }
        else { Show-Toast "$($script:Dl.Name) is installed - press Open desktop to start it." }
    }
}

# ------------------------------------------------------------------------------
# Sidebar: back up / restore
# ------------------------------------------------------------------------------
$ui.BtnBackup.Add_Click({
    if (-not $script:Distros.Count) { Show-Toast 'No distros installed - nothing to back up.' 'Warn'; return }
    $ui.BakList.ItemsSource = @($script:Distros | ForEach-Object { $_.Name })
    $cur = Get-CurrentDistro
    if ($cur) { $ui.BakList.SelectedItem = $cur.Name }
    $script:BakDir = ''
    $ui.BakTar.IsChecked = $true
    Update-BackupForm
    Open-Panel 'PanelBackup' 560
})
function Update-BackupForm {
    $ui.BakFolder.Text = $(if ($script:BakDir) { $script:BakDir } else { $NO_FOLDER })
    $ui.BtnBakOk.IsEnabled = [bool](($null -ne $ui.BakList.SelectedItem) -and $script:BakDir)
}
$ui.BakList.Add_SelectionChanged({ Update-BackupForm })
$ui.BtnBakFolder.Add_Click({ $f = Select-Folder 'Where should the backup be saved?' $Global:Config.BackupBase; if ($f) { $script:BakDir = $f; Update-BackupForm } })
$ui.BtnBakCancel.Add_Click({ Close-Dialog })
$ui.BtnBakOk.Add_Click({
    $problem = Set-DataFolder 'BackupBase' $script:BakDir   # Restore lists the backups found there
    if ($problem) { Show-Toast $problem 'Error'; return }
    $A = @{ Name = [string]$ui.BakList.SelectedItem; Dir = $script:BakDir; Ext = $(if ($ui.BakVhdx.IsChecked) { 'vhdx' } else { 'tar' }) }
    Start-Task "Backing up $($A.Name)" { Export-WslDistro $A.Name $A.Dir $A.Ext } $A {
        param($r)
        Update-DistroList
        if ($r.Ok) {
            Show-Info "Backup saved ($($r.GB) GB)" ("$($r.File)`n`n" +
                "NOTE: saved panel accounts are NOT in the backup (their passwords are locked to this Windows login). " +
                "On another PC re-add them with Add an account, switching OFF ""Also create this user inside the distro"" (the Linux user already exists inside the backup).")
        } else {
            Show-Failure "The backup FAILED (exit code $($r.ExitCode))" "Common causes: not enough free space in $(Split-Path -Parent $r.File), or that folder cannot be written to."
        }
    }
})

$script:ResFiles = @(); $script:ResPick = $null; $script:ResBase = ''
$ui.BtnRestore.Add_Click({
    $script:ResFiles = @(Get-BackupFiles)
    $ui.ResHint.Text = $(if ($script:ResFiles.Count) { "Backups in $($Global:Config.BackupBase) (the folder of your last backup), newest first:" }
                         else { 'Browse for the backup file (.tar or .vhdx) to restore.' })
    $ui.ResList.ItemsSource = @($script:ResFiles | ForEach-Object { '{0}   ({1} GB)' -f $_.Name, [math]::Round($_.Length / 1GB, 2) })
    $script:ResPick = $null; $script:ResBase = ''
    $ui.ResFile.Text = ''; $ui.ResName.Text = ''
    Update-RestoreForm
    Open-Panel 'PanelRestore' 600
})
function Update-RestoreForm {
    $name = $ui.ResName.Text.Trim()
    $ui.ResFolder.Text = $(if (-not $script:ResBase) { $NO_FOLDER } elseif ($name) { Join-Path $script:ResBase $name } else { $script:ResBase })
    $ui.BtnResOk.IsEnabled = [bool]($script:ResPick -and $name -and $script:ResBase)
}
function Set-RestoreFile([string]$path) {
    $script:ResPick = $path
    $ui.ResFile.Text = $path
    $ui.ResName.Text = Get-BackupDistroName $path
    Update-RestoreForm
}
$ui.ResList.Add_SelectionChanged({ if ($ui.ResList.SelectedIndex -ge 0) { Set-RestoreFile $script:ResFiles[$ui.ResList.SelectedIndex].FullName } })
$ui.BtnResBrowse.Add_Click({
    $d = New-Object System.Windows.Forms.OpenFileDialog
    $d.Filter = 'WSL backups (*.tar;*.vhdx)|*.tar;*.vhdx|All files (*.*)|*.*'
    $d.Title = 'Pick a backup to restore'
    if ($d.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $ui.ResList.SelectedIndex = -1; Set-RestoreFile $d.FileName }
})
$ui.ResName.Add_TextChanged({ Update-RestoreForm })
$ui.BtnResFolder.Add_Click({
    $f = Select-Folder 'Where should the restored distro be stored? (a folder named after it is created inside)' $Global:Config.WslBase
    if ($f) { $script:ResBase = $f; Update-RestoreForm }
})
$ui.BtnResCancel.Add_Click({ Close-Dialog })
$ui.BtnResOk.Add_Click({
    $A = @{ File = $script:ResPick; Name = $ui.ResName.Text.Trim(); Loc = (Join-Path $script:ResBase $ui.ResName.Text.Trim()) }
    $problem = Get-RestoreProblem $A.File $A.Name $A.Loc
    if (-not $problem) { $problem = Set-DataFolder 'WslBase' $script:ResBase }
    if ($problem) { Show-Toast $problem 'Error'; return }
    $script:SelectNext = $A.Name
    Start-Task "Restoring $($A.Name)" { Import-WslDistro $A.File $A.Name $A.Loc } $A {
        param($r)
        Update-DistroList
        if ($r.Ok) {
            $who = $(if ($r.DefaultUser) { "Default login set to '$($r.DefaultUser)' (the user found inside the backup)." } else { 'No normal user was found inside it, so it opens as root.' })
            Show-Info 'Restored' ("Done - it is restored with all its programs and files.`n$who`n`n" +
                "Saved panel accounts are not part of a backup: for auto-login use Add an account and switch OFF ""Also create this user inside the distro"" (the Linux user already exists).")
        } else {
            Show-Failure "The restore FAILED (exit code $($r.ExitCode))" 'Common causes: not enough free space, or the file is incomplete / damaged.'
        }
    }
})

# ------------------------------------------------------------------------------
# Sidebar: the other tools
# ------------------------------------------------------------------------------
$ui.BtnCloseRun.Add_Click({
    $running = @(Get-RunningDistros)
    if (-not $running.Count) { Show-Toast 'No distros are running - nothing to close.' 'Warn'; return }
    Show-Pick 'Close a running distro' 'Stops it and frees its RAM (wsl --terminate).' $running 'Close it' {
        Start-Task "Closing $($script:Picked)" { Stop-OneDistro $A.Name } @{ Name = $script:Picked } { param($x) Update-DistroList; Show-Toast "$($script:Picked) is stopped." }
    } 'Close ALL running distros' {
        Start-Task 'Closing every distro' { Stop-AllWsl } @{} { param($x) Update-DistroList; Show-Toast 'Everything is stopped and the WSL memory is freed.' }
    }
})
$ui.BtnShutdown.Add_Click({
    Show-Message 'Shut down ALL WSL' ("This stops EVERY running distro and frees the memory the WSL VM is using (wsl --shutdown).`n`n" +
        '(A separate "Vmmem" in Task Manager is NOT Linux - this does not affect it.)') @(
        @{ Text = 'Shut down all'; Do = {
            Start-Task 'Shutting down WSL' { Stop-AllWsl } @{} {
                param($freed)
                Update-DistroList
                if ($freed) { Show-Toast 'WSL is shut down and its memory is freed.' } else { Show-Toast 'WSL is shutting down - its memory is freed within a minute.' }
            } } },
        @{ Text = 'Cancel' })
})
$ui.BtnCompactAny.Add_Click({
    if (-not $script:Distros.Count) { Show-Toast 'No distros installed - nothing to compact.' 'Warn'; return }
    Show-Pick 'Compact a disk' 'Which distro''s disk should give its unused space back to Windows?' @($script:Distros | ForEach-Object { $_.Name }) 'Next' {
        Show-CompactDialog $script:Picked
    }
})

# Memory / CPU limits
function Show-LimitsPanel {
    $path = Get-WslConfigPath
    $ui.LimPath.Text = "Settings file: $path"
    $ui.LimCurrent.Text = $(if (Test-Path -LiteralPath $path) { (Get-Content -LiteralPath $path) -join "`n" } else { 'No .wslconfig yet (WSL uses its defaults: up to 50% of your RAM).' })
    $ui.LimMem.Text = ''; $ui.LimCpu.Text = ''; $ui.LimSwap.Text = ''
    Open-Panel 'PanelLimits' 680
}
function Set-Limits($mem, $cpu, $swap) {
    Set-WslLimits $mem $cpu $swap
    Close-Dialog
    if ($null -eq $mem) { Show-Toast 'Limits removed - WSL uses its defaults after Shut down all.' }
    else { Show-Toast "Limits set ($mem RAM, $cpu CPUs, $swap swap) - active after Shut down all." }
}
$ui.BtnLimits.Add_Click({ Show-LimitsPanel })
$ui.BtnLimLight.Add_Click({ Set-Limits '4GB' '2' '2GB' })
$ui.BtnLimMedium.Add_Click({ Set-Limits '8GB' '4' '4GB' })
$ui.BtnLimHeavy.Add_Click({ Set-Limits '16GB' '6' '8GB' })
$ui.BtnLimCustom.Add_Click({
    $m = $ui.LimMem.Text.Trim(); $c = $ui.LimCpu.Text.Trim(); $s = $ui.LimSwap.Text.Trim()
    if (-not (Test-LimitValues $m $c $s)) { Show-Toast 'Those values do not look right (use e.g. 6GB, 4, 2GB) - nothing changed.' 'Error'; return }
    Set-Limits $m $c $s
})
$ui.BtnLimReset.Add_Click({ Set-Limits $null $null $null })
$ui.BtnLimClose.Add_Click({ Close-Dialog })

# Storage locations: where every distro, the last backups and the settings are
function Show-FoldersPanel {
    $rows = @(foreach ($d in $script:Distros) {
        $vhd = Get-DistroVhdInfo $d.Name
        [pscustomobject]@{ Name = '{0}   ({1:N1} GB)' -f $d.Name, [double]$vhd.SizeGB; Path = $(if ($vhd.BasePath) { $vhd.BasePath } else { 'Location not found' }) }
    })
    $ui.FolDistros.ItemsSource = $rows
    $ui.FolNoDistros.Visibility = $(if ($rows.Count) { 'Collapsed' } else { 'Visible' })
    $ui.FolBackup.Text = $(if ($Global:Config.BackupBase) { $Global:Config.BackupBase } else { 'No backup made yet' })
    $ui.BtnFolBackup.IsEnabled = [bool]$Global:Config.BackupBase
    $ui.FolConfig.Text = $CONFIG_FOLDER
    Open-Panel 'PanelFolders' 640
}
$ui.BtnFolders.Add_Click({ Show-FoldersPanel })
$ui.FolDistros.AddHandler([Windows.Controls.Button]::ClickEvent, [Windows.RoutedEventHandler]{
    param($s, $e)
    Open-InExplorer ([string]$e.OriginalSource.Tag)
})
$ui.BtnFolBackup.Add_Click({ Open-InExplorer $Global:Config.BackupBase })
$ui.BtnFolConfig.Add_Click({ Open-InExplorer $CONFIG_FOLDER })
$ui.BtnFolClose.Add_Click({ Close-Dialog })

$ui.BtnUpdate.Add_Click({
    Show-Message 'Update / repair WSL' ("This updates the WSL platform (fixes many ""won't start"" / kernel problems). It needs administrator rights - click YES on the Windows prompt.`n`n" +
        'Your distros and their files are NOT touched.') @(
        @{ Text = 'Update WSL now'; Do = {
            Start-Task 'Updating WSL (in the administrator window)' { Update-WslPlatform } @{} {
                param($ok)
                if ($ok) { Show-Toast 'WSL update finished. Restart Windows if the update window asked you to.' }
                else { Show-Failure 'Nothing was updated' 'The administrator prompt was declined or failed.' }
            } } },
        @{ Text = 'Cancel' })
})
$ui.BtnTheme.Add_Click({ Set-Theme $(if ($script:Theme -eq 'Dark') { 'Light' } else { 'Dark' }); Update-DistroList })

# Esc / a click beside a dialog closes it - but never while a task runs.
$ui.Overlay.Add_MouseLeftButtonDown({ param($s, $e) if ($e.OriginalSource -eq $ui.Overlay -and -not $script:TaskHandle) { Close-Dialog } })
# Keyboard: Esc closes a dialog, Enter presses its main button, F5 refreshes,
# Ctrl+1 to Ctrl+9 pick a distro.
$win.Add_KeyDown({
    param($s, $e)
    if ($script:TaskHandle) { return }
    $dialog = ($ui.Overlay.Visibility -eq 'Visible')
    $ctrl = ([Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Control) -ne 0
    if ($dialog) {
        if ($e.Key -eq 'Escape') { Close-Dialog; $e.Handled = $true }
        elseif ($e.Key -eq 'Return' -and $DefaultButtons.ContainsKey($script:OpenPanel)) {
            Invoke-Button $ui[$DefaultButtons[$script:OpenPanel]]; $e.Handled = $true
        }
    } elseif ($e.Key -eq 'F5') {
        Update-DistroList; $e.Handled = $true
    } elseif ($ctrl -and $e.Key -ge [Windows.Input.Key]::D1 -and $e.Key -le [Windows.Input.Key]::D9) {
        $i = [int]$e.Key - [int][Windows.Input.Key]::D1
        if ($i -lt $ui.DistroList.Items.Count) { $ui.DistroList.SelectedIndex = $i; [void]$ui.DistroList.Focus() }
        $e.Handled = $true
    }
})
$win.Add_Closing({ param($s, $e) if ($script:TaskHandle) { $e.Cancel = $true; Show-Toast 'Please wait - a task is still running.' 'Warn' } })

# Anything unexpected inside a click is shown instead of closing the window.
$win.Dispatcher.Add_UnhandledException({
    param($s, $e)
    $e.Handled = $true
    Show-Failure 'Something went wrong' $e.Exception.Message
})

# ------------------------------------------------------------------------------
# First run: WSL itself not installed yet
# ------------------------------------------------------------------------------
function Show-FirstRun {
    Show-Message 'First-time setup - installing WSL' ("WSL (Windows Subsystem for Linux) is not set up on this PC yet. This is the one-time step that lets you run Linux on Windows.`n`n" +
        "What will happen:`n" +
        "  1. A Windows security prompt (UAC) asks for administrator rights - click YES. This is required to turn WSL on.`n" +
        "  2. Windows turns on the needed features and downloads WSL.`n" +
        "  3. If Windows says a RESTART is required, restart your PC, then run this panel again.") @(
        @{ Text = 'Set up WSL now'; Do = {
            Start-Task 'Installing WSL (in the administrator window)' { Install-WslPlatform } @{} {
                param($state)
                switch ($state) {
                    'READY' { Update-DistroList; Show-Toast 'WSL is installed and ready. Use Download a distro to get your first one.' }
                    'MISSING' {
                        Show-Info 'WSL did not get installed' ('This happens if you clicked NO on the security prompt, or the administrator window showed an error (for example no internet). Run this panel again to retry.')
                    }
                    default {
                        Show-Info 'Restart Windows to finish' ("WSL was set up but Windows needs a RESTART to finish enabling it.`n  1. Restart your PC.`n  2. Run this WSL Control Panel again.`n  3. Use Download a distro to get your first Linux distro.")
                    }
                }
            } } },
        @{ Text = 'Not now' })
}

# ------------------------------------------------------------------------------
# Start
# ------------------------------------------------------------------------------
$script:Theme = Get-WindowsTheme
$script:Mica = Enable-Mica
if ($script:Mica) { $script:Chrome = Enable-TitleBar }
Set-Theme $script:Theme
$appIcon = New-AppIconBitmap 64 (Get-WindowsAccent)
$win.Icon = $appIcon
$ui.AppIcon.Source = $appIcon
$ui.TitleIcon.Source = $appIcon
Initialize-Worker
Update-DistroList

if ($Validate) {
    # Exercise the dialogs and the background worker without showing anything.
    Show-Message 'Test' 'Message dialog' @(@{ Text = 'OK' }, @{ Text = 'Cancel' })
    Open-UserDialog 'add' 'TestDistro'
    Show-Pick 'Pick' 'A list' @('one', 'two') 'OK' { }
    foreach ($p in $Panels) { Open-Panel $p }
    Show-LimitsPanel; Show-FoldersPanel; Close-Dialog
    Set-Theme 'Light'; Set-Theme 'Dark'
    $ps = [powershell]::Create(); $ps.Runspace = $script:Rs
    [void]$ps.AddScript('Test-LinuxUserName ''alex''')
    $ok = $ps.Invoke()
    if (-not $ok -or -not $ok[0]) { throw 'The background worker did not load the engine.' }
    Show-Toast 'Test' 'Ok'; Show-Toast 'Test' 'Warn'; Show-Toast 'Test' 'Error'
    # Motion, keyboard and live status.
    $script:Motion = $true; Start-PageEntrance; Close-Dialog; $script:ClosedAt = [datetime]::MinValue; Open-Panel 'PanelMessage'
    $script:Motion = $false; Start-PageEntrance; Close-Dialog
    foreach ($k in $DefaultButtons.Keys) { if (-not $ui[$DefaultButtons[$k]]) { throw "No main button for $k" } }
    Update-LiveStatus; [void](Get-WslMemoryLimitGB)
    Update-DownloadForm; Update-BackupForm; Update-RestoreForm
    if ($ui.BtnDlOk.IsEnabled -or $ui.BtnBakOk.IsEnabled -or $ui.BtnResOk.IsEnabled) { throw 'A save button is on before a folder was chosen.' }
    $win.WindowState = 'Maximized'; Update-MaximizedMargin; $win.WindowState = 'Normal'
    "Window built: $($ui.Count) named elements, $($Panels.Count) dialogs, worker OK, $($script:Distros.Count) distros found, Mica: $($script:Mica), title bar: $($script:Chrome), accent: $(Get-WindowsAccent), RAM: $([math]::Round($script:TotalRamGB, 1)) GB"
    exit 0
}

$win.Add_ContentRendered({
    $script:LiveTimer.Start()
    Unblock-PanelFiles
    if ((Get-WslState) -ne 'Ready') { Show-FirstRun }
})
[void]$win.ShowDialog()
$script:Rs.Dispose()
