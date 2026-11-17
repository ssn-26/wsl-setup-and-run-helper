# ==============================================================================
# WSL Control Panel - installer
#
# Install or update (paste into PowerShell, no administrator needed):
#   irm https://raw.githubusercontent.com/ssn-26/wsl-setup-and-run-helper/main/install.ps1 | iex
#
# It downloads the panel straight from GitHub (so Windows shows no "downloaded
# from the internet" warnings), puts it in a folder you choose (it asks the
# first time; updates reuse that folder), builds "WSL Control Panel.exe"
# with the C# compiler that comes with Windows, and adds it to the Start menu,
# the desktop and Settings > Apps (to uninstall). Running it again updates the
# panel and keeps your saved logins and settings (the data folder).
#
# From an unzipped copy instead: double-click Install.bat,
# or  powershell -ExecutionPolicy Bypass -File install.ps1 [-From <folder>]
# Remove:  install.ps1 -Uninstall  (or Settings > Apps > WSL Control Panel)
#
# Keep this file plain ASCII (Windows PowerShell 5.1 reads it as ANSI).
# ==============================================================================
[CmdletBinding()]
param(
    [string]$From = '',
    [string]$InstallDir = '',
    [string]$Branch = 'main',
    [switch]$Uninstall,
    [switch]$NoShortcuts,
    [switch]$NoLaunch
)

# Everything is inside functions, so pasting this into a PowerShell window
# (irm | iex) never changes that window's settings or closes it.

function Write-Step([string]$text) { Write-Host "  $text" }

function Get-PanelVersion([string]$dir) {
    $text = Get-Content -LiteralPath (Join-Path $dir 'app\windows\WSL-Control-Panel.ps1') -Raw
    if ($text -match "PANEL_VERSION\s*=\s*'([^']+)'") { return $Matches[1] }
    return '0.0.0'
}

function Assert-PanelClosed {
    if (Get-Process -Name 'WSL Control Panel' -ErrorAction SilentlyContinue) {
        throw 'The WSL Control Panel is open. Close it, then run this again.'
    }
}

$UNINSTALL_KEY = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\WSLControlPanel'
# The Settings > Apps entry of the Setup wizard (build\setup.iss AppId).
$SETUP_KEY = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{11AE9744-F39D-4894-85B0-0C6FC37A1F67}_is1'
$SHORTCUT_NAME = 'WSL Control Panel.lnk'
$EXE_NAME = 'WSL Control Panel.exe'

function Get-ShortcutPaths {
    return @((Join-Path ([Environment]::GetFolderPath('Programs')) $SHORTCUT_NAME),
             (Join-Path ([Environment]::GetFolderPath('Desktop')) $SHORTCUT_NAME))
}

# Copies what the app needs from $src to $dest - app\ and this
# installer (kept for updates and -Uninstall) - and removes files older
# versions put there. The data folder in $dest is never touched. The saved logins and settings of an older unzipped copy
# (data\config in $src) are brought along when $dest has none yet - never its
# Linux disks or backups, which stay where they are.
function Copy-PanelFiles([string]$src, [string]$dest) {
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    if ((Resolve-Path -LiteralPath $src).Path.TrimEnd('\') -eq (Resolve-Path -LiteralPath $dest).Path.TrimEnd('\')) { return }
    $target = Join-Path $dest 'app'
    if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
    Copy-Item -LiteralPath (Join-Path $src 'app') -Destination $target -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $src 'install.ps1') -Destination (Join-Path $dest 'install.ps1') -Force
    # (powershell\ and bash\ held the app before 2.5.0; unins000.* belong to
    # the Setup wizard, which this install replaces.)
    foreach ($old in 'powershell', 'bash', 'launcher', 'WSL-Control-Panel.bat', 'Install.bat', 'README.md', 'LICENSE', 'unins000.exe', 'unins000.dat') {
        Remove-Item -LiteralPath (Join-Path $dest $old) -Recurse -Force -ErrorAction SilentlyContinue
    }
    $oldConfig = Join-Path $src 'data\config'
    $newConfig = Join-Path $dest 'data\config'
    # Only when there is something to bring: an empty data\config (a fresh copy
    # of the code) would only make the message below wrong.
    $hasConfig = (Test-Path -LiteralPath $oldConfig) -and
                 [bool](Get-ChildItem -LiteralPath $oldConfig -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1)
    if ($hasConfig -and -not (Test-Path -LiteralPath $newConfig)) {
        Write-Step 'Bringing along your saved logins and settings ...'
        New-Item -ItemType Directory -Force -Path (Join-Path $dest 'data') | Out-Null
        Copy-Item -LiteralPath $oldConfig -Destination $newConfig -Recurse -Force
    }
}

# Builds "WSL Control Panel.exe" into $dest from the source in $src
# (build\build-launcher.ps1; the source itself is not installed). Always in Windows
# PowerShell 5.1, even when this runs in PowerShell 7: the launcher hosts the
# PowerShell that comes with Windows.
function Build-Launcher([string]$src, [string]$dest) {
    $build = Join-Path $src 'build\build-launcher.ps1'
    if (-not (Test-Path -LiteralPath $build)) { throw 'The launcher source is missing - install with the one-line command instead.' }
    $ps51 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $out = & $ps51 -NoProfile -ExecutionPolicy Bypass -STA -File $build -Source $src -Dest $dest
    $exe = Join-Path $dest $EXE_NAME
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $exe)) {
        throw "Building $EXE_NAME failed. $($out -join "`n")"
    }
    return $exe
}

function New-Shortcut([string]$path, [string]$exe) {
    $sh = New-Object -ComObject WScript.Shell
    $lnk = $sh.CreateShortcut($path)
    $lnk.TargetPath = $exe
    $lnk.WorkingDirectory = Split-Path -Parent $exe
    $lnk.IconLocation = "$exe,0"
    $lnk.Description = 'Open, manage and back up your WSL Linux distros'
    $lnk.Save()
}

function Register-Uninstall([string]$dest, [string]$exe) {
    if ($dest.Length -gt 3) { $dest = $dest.TrimEnd('\') }   # a trailing \ would break the quoted path below
    Remove-Item -Path $SETUP_KEY -Recurse -Force -ErrorAction SilentlyContinue   # the Setup wizard's entry, if any
    New-Item -Path $UNINSTALL_KEY -Force | Out-Null
    $size = [int]((Get-ChildItem -LiteralPath $dest -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1KB)
    $values = @{
        DisplayName = 'WSL Control Panel'; DisplayVersion = (Get-PanelVersion $dest); Publisher = 'ssn-26'
        DisplayIcon = $exe; InstallLocation = $dest; URLInfoAbout = 'https://github.com/ssn-26/wsl-setup-and-run-helper'
        UninstallString = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""$(Join-Path $dest 'install.ps1')"" -Uninstall -InstallDir ""$dest"""
    }
    foreach ($k in $values.Keys) { New-ItemProperty -Path $UNINSTALL_KEY -Name $k -Value $values[$k] -PropertyType String -Force | Out-Null }
    foreach ($k in 'NoModify', 'NoRepair') { New-ItemProperty -Path $UNINSTALL_KEY -Name $k -Value 1 -PropertyType DWord -Force | Out-Null }
    New-ItemProperty -Path $UNINSTALL_KEY -Name EstimatedSize -Value $size -PropertyType DWord -Force | Out-Null
}

# Where an earlier install put the app: the Settings > Apps entry of this
# installer or of the Setup wizard. '' when it is not installed.
function Get-InstalledDir {
    foreach ($key in $UNINSTALL_KEY, $SETUP_KEY) {
        $dir = [string](Get-ItemProperty -Path $key -Name InstallLocation -ErrorAction SilentlyContinue).InstallLocation
        if ($dir -and (Test-Path -LiteralPath $dir)) { return $dir.TrimEnd('\') }
    }
    return ''
}

$INSTALL_PICKER_CS = @'
using System;
using System.Runtime.InteropServices;
public static class InstallFolderPicker {
    [ComImport, Guid("DC1C5A9C-E88A-4dde-A5A1-60F82A20AEF7")] class FileOpenDialogRCW { }
    [ComImport, Guid("42f85136-db7e-439c-85f1-e4075d135fc8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IFileDialog {
        [PreserveSig] int Show(IntPtr parent);
        void SetFileTypes(uint c, IntPtr t); void SetFileTypeIndex(uint i); void GetFileTypeIndex(out uint i);
        void Advise(IntPtr e, out uint c); void Unadvise(uint c);
        void SetOptions(uint o); void GetOptions(out uint o);
        void SetDefaultFolder(IntPtr i); void SetFolder(IntPtr i);
        void GetFolder(out IShellItem i); void GetCurrentSelection(out IShellItem i);
        void SetFileName([MarshalAs(UnmanagedType.LPWStr)] string n); void GetFileName([MarshalAs(UnmanagedType.LPWStr)] out string n);
        void SetTitle([MarshalAs(UnmanagedType.LPWStr)] string t); void SetOkButtonLabel([MarshalAs(UnmanagedType.LPWStr)] string t);
        void SetFileNameLabel([MarshalAs(UnmanagedType.LPWStr)] string t); void GetResult(out IShellItem i);
    }
    [ComImport, Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IShellItem {
        void BindToHandler(IntPtr b, ref Guid h, ref Guid r, out IntPtr p); void GetParent(out IShellItem i);
        void GetDisplayName(uint s, [MarshalAs(UnmanagedType.LPWStr)] out string n);
        void GetAttributes(uint m, out uint a); void Compare(IShellItem i, uint h, out int o);
    }
    public static string Pick(IntPtr owner, string title) {
        IFileDialog d = (IFileDialog)new FileOpenDialogRCW();
        uint o; d.GetOptions(out o);
        d.SetOptions(o | 0x20 | 0x40 | 0x800);
        d.SetTitle(title);
        if (d.Show(owner) != 0) return "";
        IShellItem r; d.GetResult(out r);
        string path; r.GetDisplayName(0x80058000, out path);
        return path;
    }
}
'@

# Asks where to install (there is no default). A "WSL Control Panel" folder is
# made inside the folder picked, unless it already has that name. Returns ''
# when the user cancels.
function Select-InstallDir {
    $picked = ''
    if ([Threading.Thread]::CurrentThread.GetApartmentState() -eq 'STA') {
        Add-Type -AssemblyName System.Windows.Forms
        $owner = New-Object System.Windows.Forms.Form -Property @{ TopMost = $true; ShowInTaskbar = $false }
        $title = 'Choose where to install WSL Control Panel (a "WSL Control Panel" folder is made inside)'
        try {
            # The standard Windows "Select folder" window (the same as in the app).
            try {
                if (-not ('InstallFolderPicker' -as [type])) { Add-Type -TypeDefinition $INSTALL_PICKER_CS -Language CSharp }
                $picked = [InstallFolderPicker]::Pick($owner.Handle, $title)
            } catch {
                $d = New-Object System.Windows.Forms.FolderBrowserDialog
                $d.Description = $title
                $d.ShowNewFolderButton = $true
                try { if ($d.ShowDialog($owner) -eq [System.Windows.Forms.DialogResult]::OK) { $picked = $d.SelectedPath } } finally { $d.Dispose() }
            }
        } finally { $owner.Dispose() }
    } else {
        # No window possible here: ask in the console instead.
        $picked = (Read-Host '  Where should the app be installed? Type a folder, e.g. D:\Apps (Enter to cancel)').Trim().Trim('"')
    }
    if (-not $picked) { return '' }
    if ((Split-Path -Leaf $picked) -ne 'WSL Control Panel') { $picked = Join-Path $picked 'WSL Control Panel' }
    return $picked
}

# Folders like Program Files need administrator rights: say so plainly instead
# of failing halfway through copying.
function Assert-Writable([string]$dir) {
    $probe = Join-Path $dir '.wsl-control-panel-write-test'
    try {
        New-Item -ItemType Directory -Force -Path $dir -ErrorAction Stop | Out-Null
        Set-Content -LiteralPath $probe -Value '' -ErrorAction Stop
        Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
    } catch {
        throw "Windows does not let this app write to $dir. Folders like Program Files need administrator rights - run this again and choose a folder in your user folder or on another drive."
    }
}

function Install-Panel {
    $dest = $InstallDir
    $src = $From
    $tmp = $null
    try {
        Assert-PanelClosed
        if (-not $src -and $PSScriptRoot -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'app\windows\WSL-Control-Panel.ps1'))) {
            $src = $PSScriptRoot   # run from an unzipped copy
        }
        if ($src) {
            if (-not (Test-Path -LiteralPath (Join-Path $src 'app\windows\WSL-Control-Panel.ps1'))) { throw "No WSL Control Panel files in $src" }
            Write-Step "Installing from $src ..."
        } else {
            # Downloaded by PowerShell itself: no "from the internet" mark, so no warnings later.
            $url = "https://github.com/ssn-26/wsl-setup-and-run-helper/archive/refs/heads/$Branch.zip"
            Write-Step "Downloading $url ..."
            [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
            $tmp = Join-Path $env:TEMP ('wsl-control-panel-' + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $tmp | Out-Null
            $zip = Join-Path $tmp 'panel.zip'
            $ProgressPreference = 'SilentlyContinue'   # the progress bar makes 5.1 downloads very slow
            Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
            Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $tmp 'x') -Force
            $src = (Get-ChildItem -LiteralPath (Join-Path $tmp 'x') -Directory | Select-Object -First 1).FullName
        }
        Get-ChildItem -LiteralPath $src -Recurse -File | Unblock-File -ErrorAction SilentlyContinue

        if (-not $dest) {
            $dest = Get-InstalledDir
            if ($dest) {
                Write-Step "Updating the app in $dest ..."
            } else {
                Write-Step 'Choose where to install the app (a folder window opens) ...'
                $dest = Select-InstallDir
                if (-not $dest) { throw 'No folder was chosen, so nothing was installed.' }
            }
        }
        Assert-Writable $dest

        Write-Step "Copying the panel to $dest ..."
        Copy-PanelFiles $src $dest
        Get-ChildItem -LiteralPath $dest -Recurse -File | Unblock-File -ErrorAction SilentlyContinue

        Write-Step "Building $EXE_NAME ..."
        $exe = Build-Launcher $src $dest

        if (-not $NoShortcuts) {
            Write-Step 'Adding it to the Start menu and the desktop ...'
            foreach ($p in Get-ShortcutPaths) { New-Shortcut $p $exe }
        }
        Register-Uninstall $dest $exe

        Write-Host ''
        Write-Host "  WSL Control Panel $(Get-PanelVersion $dest) is installed." -ForegroundColor Green
        Write-Host '  Open it from the Start menu or the desktop. Run the same line again to update it.'
        Write-Host ''
        if (-not $NoLaunch) { Start-Process -FilePath $exe -WorkingDirectory $dest }
        return $true
    } catch {
        Write-Host ''
        Write-Host "  The installation did not finish: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ''
        return $false
    } finally {
        if ($tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

function Uninstall-Panel {
    $dest = $InstallDir
    try {
        Assert-PanelClosed
        if (-not $dest) {
            # The copy of this script inside the app folder, or the folder Windows knows.
            if ($PSScriptRoot -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot $EXE_NAME))) { $dest = $PSScriptRoot } else { $dest = Get-InstalledDir }
            if (-not $dest) { throw 'WSL Control Panel does not seem to be installed (no install folder found).' }
        }
        foreach ($p in Get-ShortcutPaths) { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue }
        Remove-Item -Path $UNINSTALL_KEY -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $dest) {
            # The program files go. Of data\ only the saved logins, settings and
            # logs may go, and only if you say so: Linux disks and backups that an
            # older version kept in data\linux / data\backups are never deleted.
            $data = Join-Path $dest 'data'
            Get-ChildItem -LiteralPath $dest -Force | Where-Object { $_.Name -ne 'data' } |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath (Join-Path $data 'config')) {
                Write-Host ''
                Write-Host "  Your saved logins and settings are in $(Join-Path $data 'config')"
                if ((Read-Host '  Delete them too? (y/N)') -match '^[yY]') {
                    foreach ($d in 'config', 'logs') { Remove-Item -LiteralPath (Join-Path $data $d) -Recurse -Force -ErrorAction SilentlyContinue }
                }
            }
            # Empty folders left by older versions can go.
            Get-ChildItem -LiteralPath $data -Directory -Force -ErrorAction SilentlyContinue |
                Where-Object { -not (Get-ChildItem -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue) } |
                Remove-Item -Force -ErrorAction SilentlyContinue
            $left = @(Get-ChildItem -LiteralPath $data -Force -ErrorAction SilentlyContinue)
            if ($left.Count) {
                Write-Host "  Kept (not deleted): $(($left | ForEach-Object { $_.FullName }) -join ', ')"
            } else {
                Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        Write-Host ''
        Write-Host '  WSL Control Panel is removed. Your WSL distros were not touched.' -ForegroundColor Green
        Write-Host ''
        return $true
    } catch {
        Write-Host "  Could not remove it: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

$ErrorActionPreferenceBefore = $ErrorActionPreference
$ErrorActionPreference = 'Stop'
try {
    Write-Host ''
    Write-Host '  WSL Control Panel' -ForegroundColor Cyan
    if ($Uninstall) { $ok = Uninstall-Panel } else { $ok = Install-Panel }
} finally {
    $ErrorActionPreference = $ErrorActionPreferenceBefore
}
if ($Uninstall -and $PSCommandPath) {
    # Started from Settings > Apps: keep the window open long enough to read it.
    [void](Read-Host '  Press Enter to close')
}
# Run as a file (not pasted): report failure through the exit code.
if (-not $ok -and $PSCommandPath) { exit 1 }
