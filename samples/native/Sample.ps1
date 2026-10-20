# ==============================================================================
# WSL Control Panel - NATIVE (WPF) SAMPLE. Runs on fake data: nothing in WSL is
# touched. -Validate loads the window and wires it up without showing it (CI).
# Keep this file plain ASCII (Windows PowerShell 5.1).
# ==============================================================================
param([switch]$Validate)
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# The launcher hides the console, so any error is shown in a message box (and
# printed, for -Validate in CI) instead of vanishing.
trap {
    if (-not $Validate) { [void][Windows.MessageBox]::Show("The sample hit an error:`n`n$($_.Exception.Message)", 'WSL Control Panel sample') }
    Write-Error $_ -ErrorAction Continue
    exit 1
}

$raw = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Sample.xaml') -Raw -Encoding UTF8
$win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$raw)))

# Every x:Name in the XAML becomes $ui.<Name>
$ui = @{}
foreach ($m in [regex]::Matches($raw, 'x:Name="([A-Za-z0-9_]+)"')) {
    $n = $m.Groups[1].Value
    $el = $win.FindName($n)
    if ($el) { $ui[$n] = $el }
}

# ------------------------------------------------------------------ themes
$Themes = @{
    Dark  = @{ Bg = '#0F1115'; Sidebar = '#14171D'; Card = '#1A1E26'; Raised = '#232935'; Line = '#2A303C'
               Text = '#E8EAEF'; Muted = '#8B93A3'; Accent = '#4FB6FF'; AccentInk = '#04121F'; AccentSoft = '#1E3448'
               Ok = '#3CCF91'; OkSoft = '#173A2E'; Danger = '#FF6B6B'; DangerSoft = '#3A1F24'; LogBg = '#0A0C10' }
    Light = @{ Bg = '#F4F6FA'; Sidebar = '#FFFFFF'; Card = '#FFFFFF'; Raised = '#EEF1F6'; Line = '#E1E5EC'
               Text = '#161A22'; Muted = '#677084'; Accent = '#0A78D1'; AccentInk = '#FFFFFF'; AccentSoft = '#E1EEFA'
               Ok = '#12945F'; OkSoft = '#DDF2E8'; Danger = '#D33A3A'; DangerSoft = '#FBE6E6'; LogBg = '#0A0C10' }
}
$script:Theme = 'Dark'
function Set-Theme([string]$name) {
    foreach ($k in $Themes[$name].Keys) {
        $win.Resources[$k] = New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($Themes[$name][$k]))
    }
    $script:Theme = $name
    $ui.BtnTheme.Content = $(if ($name -eq 'Dark') { 'Switch to light theme' } else { 'Switch to dark theme' })
    Update-List
}

# ------------------------------------------------------------------ fake data
function New-Distro($name, $pretty, $color, $state, $size, $port, $systemd, $default, [string[]]$users) {
    $d = [pscustomobject]@{
        Name = $name; Pretty = $pretty; Initial = $pretty.Substring(0, 1); Color = $color; State = $state
        Size = $size; Port = $port; Systemd = $systemd; IsDefault = $default
        Users = (New-Object System.Collections.ArrayList); Meta = ''; Dot = ''
    }
    foreach ($u in $users) { [void]$d.Users.Add($u) }
    return $d
}
$script:Distros = New-Object System.Collections.ArrayList
[void]$Distros.Add((New-Distro 'Ubuntu-24.04' 'Ubuntu 24.04 LTS' '#E95420' 'Running' 12.3 3390 $true $true @('shreyas')))
[void]$Distros.Add((New-Distro 'kali-linux' 'Kali Linux' '#367BF0' 'Stopped' 8.1 3390 $false $false @()))
[void]$Distros.Add((New-Distro 'archlinux' 'Arch Linux' '#1793D1' 'Stopped' 3.4 3391 $true $false @('shreyas')))
$Online = @(
    @('Ubuntu', 'Ubuntu', '#E95420'), @('Ubuntu-24.04', 'Ubuntu 24.04 LTS', '#E95420'), @('Debian', 'Debian GNU/Linux', '#D70A53'),
    @('kali-linux', 'Kali Linux', '#367BF0'), @('archlinux', 'Arch Linux', '#1793D1'), @('FedoraLinux-42', 'Fedora Linux 42', '#51A2DA'),
    @('openSUSE-Tumbleweed', 'openSUSE Tumbleweed', '#73BA25'), @('AlmaLinux-9', 'AlmaLinux OS 9', '#FF4649')
) | ForEach-Object { [pscustomobject]@{ Name = $_[0]; Pretty = $_[1]; Color = $_[2]; Initial = $_[1].Substring(0, 1) } }
$ui.OnlineList.ItemsSource = $Online

# ------------------------------------------------------------------ rendering
function Update-List {
    $okHex = $Themes[$script:Theme].Ok; $mutedHex = $Themes[$script:Theme].Muted
    foreach ($d in $Distros) {
        $d.Meta = '{0} {1} {2:N1} GB' -f $d.State, [char]0x00B7, $d.Size
        $d.Dot = $(if ($d.State -eq 'Running') { $okHex } else { $mutedHex })
    }
    $sel = $ui.DistroList.SelectedIndex
    $ui.DistroList.ItemsSource = $null
    $ui.DistroList.ItemsSource = $Distros
    $ui.DistroList.SelectedIndex = [math]::Max(0, [math]::Min($sel, $Distros.Count - 1))
    $on = @($Distros | Where-Object { $_.State -eq 'Running' }).Count
    $ui.WslMem.Text = "$on of $($Distros.Count) distros on " + [char]0x00B7 + " $([math]::Round($on * 3.1, 1)) GB RAM"
    $ui.WslState.Text = $(if ($on) { 'WSL is running' } else { 'WSL is stopped' })
}

function Get-Current { return $ui.DistroList.SelectedItem }

function Show-Distro {
    $d = Get-Current
    if (-not $d) { return }
    $ui.HeroAvatar.Background = New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($d.Color))
    $ui.HeroInitial.Text = $d.Initial
    $ui.HeroName.Text = $d.Pretty
    $ui.HeroId.Text = $d.Name
    $running = ($d.State -eq 'Running')
    $ui.StateText.Text = $d.State
    $ui.StatePill.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, $(if ($running) { 'OkSoft' } else { 'Raised' }))
    $ui.StateText.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, $(if ($running) { 'Ok' } else { 'Muted' }))
    $ui.StateDot.SetResourceReference([Windows.Shapes.Shape]::FillProperty, $(if ($running) { 'Ok' } else { 'Muted' }))
    $ui.BtnStartStop.Content = $(if ($running) { 'Stop' } else { 'Start' })
    $ui.StatDisk.Text = ('{0:N1} GB' -f $d.Size)
    $ui.StatPort.Text = [string]$d.Port
    $ui.StatUser.Text = $(if ($d.Users.Count) { $d.Users[0] } else { 'root' })
    $ui.PortBox.Text = [string]$d.Port
    $ui.SystemdSwitch.IsChecked = $d.Systemd
    $ui.DeleteHint.Text = "Erases $($d.Pretty) and every file inside it. Back it up first if you might need it."
    $ui.AccountList.ItemsSource = @($d.Users | ForEach-Object { [pscustomobject]@{ Name = $_; Initial = $_.Substring(0, 1).ToUpper() } })
    $ui.NoUsers.Visibility = $(if ($d.Users.Count) { 'Collapsed' } else { 'Visible' })
}

# ------------------------------------------------------------------ toast + dialogs
$script:ToastTimer = New-Object Windows.Threading.DispatcherTimer
$script:ToastTimer.Interval = [TimeSpan]::FromSeconds(3.5)
$script:ToastTimer.Add_Tick({ $ui.Toast.Visibility = 'Collapsed'; $script:ToastTimer.Stop() })
function Show-Toast([string]$msg) {
    $ui.ToastText.Text = $msg
    $ui.Toast.Visibility = 'Visible'
    $script:ToastTimer.Stop(); $script:ToastTimer.Start()
}

function Open-Panel([string]$name, [int]$width = 500) {
    foreach ($p in 'PanelUser', 'PanelTask', 'PanelDelete', 'PanelDownload') { $ui[$p].Visibility = 'Collapsed' }
    $ui[$name].Visibility = 'Visible'
    $ui.DialogCard.Width = $width
    $ui.Overlay.Visibility = 'Visible'
}
function Close-Dialog { $ui.Overlay.Visibility = 'Collapsed' }

# Create user
# $then names what happens after the user is created: 'open' (open the
# desktop), 'ready' (say the new distro is ready) or '' (nothing).
$script:UserFor = $null; $script:UserThen = ''
function Open-CreateUser($d, [string]$then) {
    $script:UserFor = $d; $script:UserThen = $then
    $ui.UserIntro.Text = "$($d.Pretty) only has root, which cannot log in to a desktop. This makes your own user with admin (sudo) rights, sets up the desktop session and saves the login (encrypted) for auto-login."
    $ui.UName.Text = 'shreyas'; $ui.P1.Password = ''; $ui.P2.Password = ''
    Test-UserForm
    Open-Panel 'PanelUser'
    [void]$ui.P1.Focus()
}
function Test-UserForm {
    $nameOk = $ui.UName.Text -cmatch '^[a-z_][a-z0-9_-]{0,31}$'
    if ($ui.UName.Text -and -not $nameOk) {
        $ui.UHint.Text = 'Use lowercase letters, digits, - and _, starting with a letter'
        $ui.UHint.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'Danger')
    } else {
        $ui.UHint.Text = 'Lowercase letters, digits, - and _'
        $ui.UHint.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'Muted')
    }
    $pwOk = $ui.P1.Password.Length -gt 0 -and $ui.P1.Password -ceq $ui.P2.Password
    if ($ui.P2.Password) {
        $ui.PHint.Text = $(if ($pwOk) { 'Passwords match' } else { 'The passwords do not match' })
        $ui.PHint.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, $(if ($pwOk) { 'Ok' } else { 'Danger' }))
    } else { $ui.PHint.Text = ' ' }
    $ui.BtnUserOk.IsEnabled = $nameOk -and $pwOk
}
$ui.UName.Add_TextChanged({ Test-UserForm })
$ui.P1.Add_PasswordChanged({ Test-UserForm })
$ui.P2.Add_PasswordChanged({ Test-UserForm })
$ui.BtnUserCancel.Add_Click({ Close-Dialog })
$ui.BtnUserOk.Add_Click({
    $d = $script:UserFor; $u = $ui.UName.Text
    Start-FakeTask "Creating $u in $($d.Pretty)" @(
        "Creating Linux user '$u'...", 'Installing the sudo package...', "Configuring admin rights for '$u'...",
        'Setting up XFCE session and audio forwarding...', 'Setting the password...', "'$u' is now the default login."
    ) 'user-created' $d $u
})

# Long task with progress (a timer plays the fake steps)
# When the fake steps finish, Complete-Task does $script:TaskAfter with
# $script:TaskDistro / $script:TaskArg (named steps, not closures: a closure
# made with GetNewClosure cannot see this script's functions).
$script:TaskLines = @(); $script:TaskIndex = 0; $script:TaskAfter = ''; $script:TaskDistro = $null; $script:TaskArg = $null
$script:TaskTimer = New-Object Windows.Threading.DispatcherTimer
$script:TaskTimer.Interval = [TimeSpan]::FromMilliseconds(650)
$script:TaskTimer.Add_Tick({
    if ($script:TaskIndex -lt $script:TaskLines.Count) {
        $line = $script:TaskLines[$script:TaskIndex]
        $ui.TaskLog.AppendText("==> $line`r`n"); $ui.TaskLog.ScrollToEnd()
        $ui.TaskStep.Text = $line
        $script:TaskIndex++
        $pct = [int](100 * $script:TaskIndex / $script:TaskLines.Count)
        $ui.TaskBar.Value = $pct; $ui.TaskPct.Text = "$pct%"
    } else {
        $script:TaskTimer.Stop()
        $ui.TaskStep.Text = 'Done'
        $ui.BtnTaskClose.IsEnabled = $true; $ui.BtnTaskClose.Content = 'Close'
        Close-Dialog
        Complete-Task
    }
})
function Complete-Task {
    $d = $script:TaskDistro; $x = $script:TaskArg
    switch ($script:TaskAfter) {
        'user-created' {
            [void]$d.Users.Add($x); Show-Distro; Show-Toast "$x is ready in $($d.Pretty)"
            if ($script:UserThen -eq 'open') { Open-FakeDesktop $d }
            elseif ($script:UserThen -eq 'ready') { Show-Toast "$($d.Pretty) is ready - press Open desktop" }
        }
        'downloaded' {
            $n = New-Distro $x.Name $x.Pretty $x.Color 'Stopped' 1.2 3390 $false $false @()
            [void]$Distros.Add($n); Update-List
            $ui.DistroList.SelectedItem = $n
            Open-CreateUser $n 'ready'
        }
        'desktop' { $d.State = 'Running'; Update-List; Show-Distro; Show-Toast "$($d.Pretty) desktop opened as $($d.Users[0])" }
        'toast' { Show-Toast $x }
    }
}
function Start-FakeTask([string]$title, [string[]]$lines, [string]$after, $distro = $null, $arg = $null) {
    $ui.TaskTitle.Text = $title; $ui.TaskLog.Text = ''; $ui.TaskBar.Value = 0; $ui.TaskPct.Text = '0%'
    $ui.TaskStep.Text = 'Starting...'; $ui.BtnTaskClose.IsEnabled = $false; $ui.BtnTaskClose.Content = 'Working...'
    $script:TaskLines = $lines; $script:TaskIndex = 0
    $script:TaskAfter = $after; $script:TaskDistro = $distro; $script:TaskArg = $arg
    Open-Panel 'PanelTask' 640
    $script:TaskTimer.Start()
}
$ui.BtnTaskClose.Add_Click({ Close-Dialog })

# Delete
$ui.DelName.Add_TextChanged({ $ui.BtnDelOk.IsEnabled = ($ui.DelName.Text -ceq (Get-Current).Name) })
$ui.BtnDelCancel.Add_Click({ Close-Dialog })
$ui.BtnDelOk.Add_Click({
    $d = Get-Current
    $Distros.Remove($d); Close-Dialog; Update-List; Show-Distro
    Show-Toast "$($d.Pretty) was deleted"
})

# Download
$ui.OnlineList.Add_SelectionChanged({ $ui.BtnDlOk.IsEnabled = ($null -ne $ui.OnlineList.SelectedItem) })
$ui.BtnDlCancel.Add_Click({ Close-Dialog })
$ui.BtnDlOk.Add_Click({
    $o = $ui.OnlineList.SelectedItem
    Start-FakeTask "Downloading $($o.Pretty)" @(
        'Reading the official distro list...', "Downloading $($o.Name) (412 MB)...",
        'Connection dropped - resuming (attempt 1 of 60)...', 'Checking the SHA-256 fingerprint... verified',
        "Installing $($o.Name) into data\linux\$($o.Name)..."
    ) 'downloaded' $null $o
})

# ------------------------------------------------------------------ main actions
function Open-FakeDesktop($d) {
    if ($d.Users.Count -eq 0) { Open-CreateUser $d 'open'; return }
    $kind = $(if ($d.Name -like '*kali*') { 'Win-KeX' } else { 'xrdp' })
    Start-FakeTask "Opening the $($d.Pretty) desktop" @(
        "Waking $($d.Name)...", "Detecting desktop type... $kind", "Starting the desktop server on port $($d.Port)...",
        'Opening Windows Remote Desktop...'
    ) 'desktop' $d
}

$ui.DistroList.Add_SelectionChanged({ Show-Distro })
$ui.BtnDesktop.Add_Click({ Open-FakeDesktop (Get-Current) })
$ui.BtnTerminal.Add_Click({ $d = Get-Current; $d.State = 'Running'; Update-List; Show-Distro; Show-Toast "Terminal opened for $($d.Pretty)" })
$ui.BtnStartStop.Add_Click({
    $d = Get-Current
    $d.State = $(if ($d.State -eq 'Running') { 'Stopped' } else { 'Running' })
    Update-List; Show-Distro; Show-Toast "$($d.Pretty) is $($d.State.ToLower())"
})
$ui.BtnAddUser.Add_Click({ Open-CreateUser (Get-Current) '' })
$ui.BtnCompact.Add_Click({ Start-FakeTask "Compacting $((Get-Current).Pretty)" @('Shutting WSL down so the disk file is free...', 'Compacting with diskpart...', 'Reclaimed 1.8 GB') 'toast' $null 'Reclaimed 1.8 GB' })
$ui.BtnDelete.Add_Click({
    $d = Get-Current
    $ui.DelTitle.Text = "Delete $($d.Pretty)?"
    $ui.DelLabel.Text = "Type $($d.Name) to confirm"
    $ui.DelName.Text = ''
    Open-Panel 'PanelDelete'
    [void]$ui.DelName.Focus()
})
$ui.BtnDownload.Add_Click({ $ui.OnlineList.SelectedIndex = -1; Open-Panel 'PanelDownload' 560 })
$ui.BtnShutdown.Add_Click({ foreach ($d in $Distros) { $d.State = 'Stopped' }; Update-List; Show-Distro; Show-Toast 'WSL is shut down and its memory is freed' })
$ui.BtnTheme.Add_Click({ Set-Theme $(if ($script:Theme -eq 'Dark') { 'Light' } else { 'Dark' }) })
# Buttons inside the account rows (Change password / Remove)
$ui.AccountList.AddHandler([Windows.Controls.Button]::ClickEvent, [Windows.RoutedEventHandler]{
    param($s, $e)
    $b = $e.OriginalSource
    if ($b.Content -eq 'Remove') {
        $d = Get-Current; $d.Users.Remove([string]$b.Tag); Show-Distro; Show-Toast "Removed saved login $($b.Tag)"
    } else { Show-Toast "Password for $($b.Tag) changed" }
})
$ui.Overlay.Add_MouseLeftButtonDown({ param($s, $e) if ($e.OriginalSource -eq $ui.Overlay -and -not $script:TaskTimer.IsEnabled) { Close-Dialog } })
$win.Add_KeyDown({ param($s, $e) if ($e.Key -eq 'Escape' -and -not $script:TaskTimer.IsEnabled) { Close-Dialog } })

Set-Theme 'Dark'
$ui.DistroList.SelectedIndex = 0
Show-Distro

if ($Validate) {
    "Sample window loaded: $($ui.Count) named elements, $($Distros.Count) fake distros."
    exit 0
}
[void]$win.ShowDialog()
