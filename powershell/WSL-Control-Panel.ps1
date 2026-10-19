# ==============================================================================
# WSL Control Panel
# Menu-driven manager for Windows Subsystem for Linux (WSL2): list / open /
# close / delete / download distros, per-distro saved accounts (passwords are
# encrypted with Windows DPAPI), XFCE desktops (xrdp + Remote Desktop, or
# Win-KeX on Kali), backup / restore, disk compaction, .wslconfig tuning.
#
# Start it with the WSL-Control-Panel.bat launcher next to this file.
# Keep this file plain ASCII: Windows PowerShell 5.1 reads a BOM-less script as
# ANSI, so any fancy character could break parsing.
# ==============================================================================

#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# WSL_UTF8=1 makes wsl.exe print UTF-8 instead of UTF-16 (children inherit it).
$env:WSL_UTF8 = '1'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
try { $OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
try { $Host.UI.RawUI.WindowTitle = 'WSL Control Panel' } catch { }

# Folder layout (this script lives in <root>\powershell):
#   <root>\WSL-Control-Panel.bat   start file
#   <root>\bash files\             the Linux-side scripts
#   <root>\data\config\            config.json + saved accounts (encrypted passwords)
#   <root>\data\backups\           backups made with [E]       (location can be changed)
#   <root>\data\linux\             one folder per distro disk  (location can be changed)
#   <root>\data\logs\              output of desktop installs
$SCRIPT_DIR = $PSScriptRoot
if (-not $SCRIPT_DIR) { $SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $SCRIPT_DIR) { $SCRIPT_DIR = (Get-Location).Path }
$ROOT_DIR = Split-Path -Parent $SCRIPT_DIR

$SCRIPTS_FOLDER  = Join-Path $ROOT_DIR 'bash files'
$DATA_FOLDER     = Join-Path $ROOT_DIR 'data'
$CONFIG_FOLDER   = Join-Path $DATA_FOLDER 'config'
$ACCOUNTS_FOLDER = Join-Path $CONFIG_FOLDER 'accounts'
$LOGS_FOLDER     = Join-Path $DATA_FOLDER 'logs'
$CONFIG_FILE     = Join-Path $CONFIG_FOLDER 'config.json'

# ------------------------------------------------------------------------------
# Configuration (data\config\config.json, created when you change a setting)
# ------------------------------------------------------------------------------
function Save-Config {
    if (-not (Test-Path -LiteralPath $CONFIG_FOLDER)) { New-Item -ItemType Directory -Path $CONFIG_FOLDER -Force | Out-Null }
    $json = $Global:Config | ConvertTo-Json
    [System.IO.File]::WriteAllText($CONFIG_FILE, $json, (New-Object System.Text.UTF8Encoding($false)))
}

function Get-Config {
    $cfg = [PSCustomObject]@{
        WslBase        = Join-Path $DATA_FOLDER 'linux'
        BackupBase     = Join-Path $DATA_FOLDER 'backups'
        DefaultRdpPort = 3390
    }
    if (Test-Path -LiteralPath $CONFIG_FILE) {
        try {
            $saved = Get-Content -LiteralPath $CONFIG_FILE -Raw | ConvertFrom-Json
            if ($saved.WslBase)        { $cfg.WslBase = [string]$saved.WslBase }
            if ($saved.BackupBase)     { $cfg.BackupBase = [string]$saved.BackupBase }
            if ($saved.DefaultRdpPort) { $cfg.DefaultRdpPort = [int]$saved.DefaultRdpPort }
        } catch { }
    }
    return $cfg
}
$Global:Config = Get-Config

# Create the data folders up front so the layout is visible (best effort - a
# folder on a drive that is not plugged in is simply skipped).
foreach ($d in @($CONFIG_FOLDER, $ACCOUNTS_FOLDER, $Global:Config.WslBase, $Global:Config.BackupBase)) {
    try { if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null } } catch { }
}

# ------------------------------------------------------------------------------
# UI helpers
# ------------------------------------------------------------------------------
function Show-Header([string]$subtitle = '') {
    try { Clear-Host } catch { }
    Write-Host '================================================================' -ForegroundColor Cyan
    Write-Host '                   WSL Control Panel' -ForegroundColor Cyan
    if ($subtitle) { Write-Host "   $subtitle" -ForegroundColor Yellow }
    Write-Host '================================================================' -ForegroundColor Cyan
    Write-Host ''
}

function Pause-Console([string]$message = 'Press any key to continue...') {
    Write-Host ''
    Write-Host " $message" -ForegroundColor DarkGray
    if ([Console]::IsInputRedirected) { $null = Read-Host } else { $null = [Console]::ReadKey($true) }
}

# Reads one trimmed line. Ends the panel cleanly if input is closed (EOF).
function Read-Line([string]$prompt) {
    $v = Read-Host $prompt
    if ($null -eq $v) { throw [System.IO.EndOfStreamException]::new('input closed') }
    return $v.Trim()
}

function Read-Secret([string]$prompt) {
    if ([Console]::IsInputRedirected) { return (Read-Line $prompt) }
    $s = Read-Host $prompt -AsSecureString
    return [System.Net.NetworkCredential]::new('', $s).Password
}

# Asks for a folder. ENTER = the default, B = go back ($null). Re-asks until the
# answer is a full path, so a stray "yes" can never become a folder name.
function Read-Folder([string]$what, [string]$default) {
    while ($true) {
        Write-Host ''
        Write-Host " $what" -ForegroundColor Yellow
        Write-Host "   Press ENTER to use:  $default"
        Write-Host '   Or type another FULL folder path (e.g. E:\Linux), or B to go back.'
        $v = (Read-Line ' Folder').Trim('"', "'")
        if ($v -eq '') { return $default }
        if ($v -ieq 'b') { return $null }
        if ($v -match '^(y|yes|n|no)$') {
            Write-Host ' That is a yes/no word, not a folder. Press ENTER for the default, or type a full path.' -ForegroundColor Red
            continue
        }
        if ($v -notmatch '^([A-Za-z]:\\|\\\\)') {
            Write-Host ' Please type a FULL path that starts with a drive letter, e.g. E:\Linux' -ForegroundColor Red
            continue
        }
        if ($v.Length -gt 3) { $v = $v.TrimEnd('\') }
        return $v
    }
}

# Asks a yes/no question. ENTER = $default; Y/YES/N/NO in any case; anything
# else asks again, so a typo never counts as an answer.
function Read-YesNo([string]$question, [bool]$default) {
    $hint = $(if ($default) { '(Y/N) [Y]' } else { '(Y/N) [N]' })
    while ($true) {
        $v = (Read-Line " $question $hint").ToUpper()
        if ($v -eq '') { return $default }
        if ($v -eq 'Y' -or $v -eq 'YES') { return $true }
        if ($v -eq 'N' -or $v -eq 'NO') { return $false }
        Write-Host ' Please answer Y or N.' -ForegroundColor Red
    }
}

# Turns a typed list number (1..count) into a 0-based index, or -1 if the
# answer is not a number in that range.
function Get-ListIndex([string]$answer, [int]$count) {
    if ($answer -match '^\d{1,6}$' -and [int]$answer -ge 1 -and [int]$answer -le $count) { return [int]$answer - 1 }
    return -1
}

# Distro names as wsl.exe accepts them (used by Download and Restore).
function Test-DistroName([string]$name) { return ($name -match '^[A-Za-z0-9._-]+$') }

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Runs PowerShell code as administrator (UAC prompt) and waits for it. The code
# travels inside the command line (-EncodedCommand), not as a file in %TEMP%
# that something else could swap out before the elevated window reads it.
# Returns $false if the prompt was declined.
function Invoke-ElevatedScript([string]$code) {
    $enc = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($code))
    try {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -Wait `
            -ArgumentList (Join-WinArgs @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $enc))
        return $true
    } catch { return $false }
}

function Get-ScriptText([string]$name) {
    $path = Join-Path $SCRIPTS_FOLDER $name
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing helper file: $path`n  Keep the 'bash files' folder next to the 'powershell' folder."
    }
    return ((Get-Content -LiteralPath $path -Raw) -replace "`r`n", "`n")
}

function ConvertTo-Base64([string]$text) {
    return [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(($text -replace "`r`n", "`n")))
}

# ------------------------------------------------------------------------------
# Running wsl.exe
# ------------------------------------------------------------------------------
# Quote one argument the way Windows programs (and wsl.exe) split command lines.
function ConvertTo-WinArg([string]$arg) {
    if ($arg -ne '' -and $arg -notmatch '[\s"]') { return $arg }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    $backslashes = 0
    foreach ($ch in $arg.ToCharArray()) {
        if ($ch -eq '\') {
            $backslashes++
        } elseif ($ch -eq '"') {
            [void]$sb.Append('\' * ($backslashes * 2 + 1)); [void]$sb.Append('"'); $backslashes = 0
        } else {
            if ($backslashes) { [void]$sb.Append('\' * $backslashes); $backslashes = 0 }
            [void]$sb.Append($ch)
        }
    }
    if ($backslashes) { [void]$sb.Append('\' * ($backslashes * 2)) }
    [void]$sb.Append('"')
    return $sb.ToString()
}

function Join-WinArgs([string[]]$list) {
    return (($list | ForEach-Object { ConvertTo-WinArg ([string]$_) }) -join ' ')
}

# One full path for every wsl.exe call (first match on PATH).
function Get-WslExe {
    if (-not $script:WslExePath) {
        $c = Get-Command wsl.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        $script:WslExePath = $(if ($c) { $c.Source } else { 'wsl.exe' })
    }
    return $script:WslExePath
}

# Runs wsl.exe hidden and captures its output. stdin is closed straight away (or
# fed from StdinText), so wsl can never swallow what the user types next.
# Arguments are passed raw - this function does the quoting.
function Invoke-WslQuiet([string[]]$ArgumentList, [string]$StdinText = $null) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = Get-WslExe
    $psi.Arguments = Join-WinArgs $ArgumentList
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $proc = [System.Diagnostics.Process]::Start($psi)
    $errTask = $proc.StandardError.ReadToEndAsync()
    if ($null -ne $StdinText) {
        $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($StdinText)
        $proc.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
        $proc.StandardInput.BaseStream.Flush()
    }
    $proc.StandardInput.Close()
    $ms = New-Object System.IO.MemoryStream
    $proc.StandardOutput.BaseStream.CopyTo($ms)
    $proc.WaitForExit()
    $raw = $ms.ToArray()

    # Old wsl.exe prints UTF-16 (full of zero bytes); WSL_UTF8=1 and Linux
    # programs print UTF-8. Detect which one we got.
    $text = ''
    if ($raw.Length -gt 0) {
        if ($raw -contains 0) { $text = [System.Text.Encoding]::Unicode.GetString($raw) }
        else { $text = [System.Text.Encoding]::UTF8.GetString($raw) }
        $text = $text.TrimStart([char]0xFEFF)
    }
    $lines = @($text -split "`r?`n" | ForEach-Object { $_.TrimEnd() } | Where-Object { $_ -ne '' })
    return @{ ExitCode = $proc.ExitCode; Output = $lines; StdError = $errTask.Result }
}

# Runs wsl.exe in THIS window so its output is visible. Returns the exit code.
# WSL's own errors are NEGATIVE numbers, so compare with 0, never "-ge 1".
function Invoke-WslInline([string[]]$ArgumentList, [string]$StdinFile = $null) {
    $sp = @{
        FilePath = (Get-WslExe); ArgumentList = (Join-WinArgs $ArgumentList)
        Wait = $true; PassThru = $true; NoNewWindow = $true
    }
    if ($StdinFile) { $sp.RedirectStandardInput = $StdinFile }
    $p = Start-Process @sp
    return $p.ExitCode
}

# Runs a bash script text as <user> inside the distro. The script travels as
# base64 and wsl's -e runs bash directly, so no extra shell re-reads it.
function Invoke-WslScript([string]$distro, [string]$user, [string]$script, [string[]]$ScriptArgs = @(), [string]$StdinText = $null) {
    $b64 = ConvertTo-Base64 $script
    $tail = ''
    if ($ScriptArgs.Count -gt 0) { $tail = ' -- ' + (($ScriptArgs | ForEach-Object { "'" + ($_ -replace "'", "'\''") + "'" }) -join ' ') }
    $cmd = "echo '$b64' | base64 -d | bash -s$tail"
    return (Invoke-WslQuiet @('-d', $distro, '-u', $user, '-e', 'bash', '-c', $cmd) $StdinText)
}

function Test-WslFiles { return (Test-Path -LiteralPath (Join-Path $env:ProgramFiles 'WSL\wsl.exe')) }

# Distros that belong to another app (Docker / Rancher Desktop). They still
# count as running (so the WSL VM is not shut down under them), but the menus
# hide them: they have no desktop, no users and their own disk layout.
function Test-SystemDistro([string]$name) { return ($name -match '^(docker-desktop|rancher-desktop)(-data)?$') }

function Get-WslDistros {
    # Never run wsl.exe before WSL is installed (see Test-WslFiles).
    if (-not (Test-WslFiles)) { return @() }
    # The names come from the registry, not "wsl -l -v": that table is translated
    # on non-English Windows (e.g. "Wird ausgefuehrt"), so it cannot be parsed.
    # "--list --running --quiet" prints bare names only, in every language.
    $lxss = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss'
    $defaultId = ''
    try { $defaultId = [string](Get-ItemProperty -Path $lxss -ErrorAction Stop).DefaultDistribution } catch { }
    $running = @{}
    $res = Invoke-WslQuiet @('--list', '--running', '--quiet')
    if ($res.ExitCode -eq 0) { foreach ($l in $res.Output) { $running[$l.Trim()] = $true } }

    $distros = @()
    foreach ($k in @(Get-ChildItem -Path $lxss -ErrorAction SilentlyContinue)) {
        $p = Get-ItemProperty -Path $k.PSPath -ErrorAction SilentlyContinue
        if (-not $p -or -not $p.DistributionName) { continue }
        $name = [string]$p.DistributionName
        $distros += [PSCustomObject]@{
            Name      = $name
            State     = $(if ($running.ContainsKey($name)) { 'Running' } else { 'Stopped' })
            Version   = $(if ($p.Version -eq 1) { '1' } else { '2' })
            IsDefault = ($k.PSChildName -eq $defaultId)
            IsSystem  = (Test-SystemDistro $name)
        }
    }
    return @($distros | Sort-Object Name)
}

function Get-RunningDistros {
    return @(Get-WslDistros | Where-Object { $_.State -eq 'Running' } | ForEach-Object { $_.Name })
}

function Get-DistroVhdInfo([string]$distroName) {
    $none = @{ BasePath = ''; VhdxPath = ''; SizeGB = 0; Exists = $false }
    try {
        $keys = Get-ChildItem -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss' -ErrorAction SilentlyContinue
        foreach ($k in $keys) {
            $p = Get-ItemProperty -Path $k.PSPath -ErrorAction SilentlyContinue
            if ($p -and $p.DistributionName -eq $distroName) {
                $base = ([string]$p.BasePath) -replace '^\\\\\?\\', ''
                $vhdx = Join-Path $base 'ext4.vhdx'
                $exists = Test-Path -LiteralPath $vhdx
                $size = 0
                if ($exists) { $size = [math]::Round((Get-Item -LiteralPath $vhdx).Length / 1GB, 2) }
                return @{ BasePath = $base; VhdxPath = $vhdx; SizeGB = $size; Exists = $exists }
            }
        }
    } catch { }
    return $none
}

# Win-KeX (Kali) keeps a VNC server running; stop it cleanly before the distro is
# terminated so the Windows-side viewer window closes too. kex --stop only stops
# the CALLER's own server, so root finds who owns each Xtigervnc and stops it as
# that user. A no-op for distros without kex.
function Stop-Kex([string]$distro) {
    $has = Invoke-WslQuiet @('-d', $distro, '--', 'bash', '-lc', 'command -v kex >/dev/null 2>&1')
    if ($has.ExitCode -ne 0) { return }
    Write-Host " Stopping Win-KeX on $distro ..." -ForegroundColor DarkGray
    # Look owners up by uid: "ps -o user=" cuts names longer than 8 characters
    # short (e.g. "shreyasn+"), and su would then fail for them.
    $cmd = 'for id in $(ps -o uid= -C Xtigervnc | sort -u); do [ "$id" = 0 ] && continue; u=$(getent passwd "$id" | cut -d: -f1); [ -n "$u" ] && su - "$u" -c ''cd ~ && kex --stop'' >/dev/null 2>&1; done; true'
    Invoke-WslQuiet @('-d', $distro, '-u', 'root', '-e', 'sh', '-c', $cmd) | Out-Null
}

function Stop-KexAll { foreach ($r in (Get-RunningDistros)) { if (-not (Test-SystemDistro $r)) { Stop-Kex $r } } }

# Kali is recognised from /etc/os-release, so a Kali restored or installed
# under another name still gets Win-KeX.
function Test-KaliDistro([string]$distro) {
    $cmd = '. /etc/os-release 2>/dev/null; [ "$ID" = kali ]'
    return ((Invoke-WslQuiet @('-d', $distro, '-e', 'sh', '-c', $cmd)).ExitCode -eq 0)
}

function Stop-Distro([string]$distro) {
    Stop-Kex $distro
    Invoke-WslQuiet @('--terminate', $distro) | Out-Null
}

# If no distro is left running, collapse the whole WSL VM so its RAM is freed.
function Free-WslVm {
    if ((Get-RunningDistros).Count -eq 0) {
        Write-Host ' No distros left running - freeing the WSL VM memory...' -ForegroundColor DarkGray
        Invoke-WslQuiet @('--shutdown') | Out-Null
    }
}

# ------------------------------------------------------------------------------
# First-time setup: installing WSL itself
# ------------------------------------------------------------------------------
# Returns $true when the panel can continue.
function Confirm-WslReady {
    # The real WSL always installs to "C:\Program Files\WSL". We check that file
    # FIRST and never run wsl.exe before it exists: on a PC where WSL was never
    # set up, Windows' built-in wsl.exe waits at a hidden 60-second "Press any
    # key to install WSL" prompt and the panel would sit on a blank window.
    if ((Test-WslFiles) -and ((Invoke-WslQuiet @('--version')).ExitCode -eq 0)) { return $true }

    Show-Header 'First-time setup - installing WSL'
    Write-Host ' WSL (Windows Subsystem for Linux) is not set up on this PC yet.' -ForegroundColor Yellow
    Write-Host ' This is the one-time step that lets you run Linux on Windows.'
    Write-Host ''
    Write-Host ' What will happen:'
    Write-Host '   1. A Windows security prompt (UAC) asks for administrator rights'
    Write-Host '      - click YES. This is required to turn WSL on.'
    Write-Host '   2. Windows turns on the needed features and downloads WSL.'
    Write-Host '   3. If Windows says a RESTART is required, restart your PC, then'
    Write-Host '      run this panel again.'
    Write-Host ''
    if (-not (Read-YesNo 'Set up WSL now?' $true)) { return $false }

    $setup = @'
Write-Host '================================================================' -ForegroundColor Cyan
Write-Host '   Installing WSL (administrator)' -ForegroundColor Cyan
Write-Host '================================================================' -ForegroundColor Cyan
Write-Host ''
Write-Host 'Turning on the Windows features WSL needs (safe if already on)...'
dism /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
dism /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
Write-Host ''
Write-Host 'Installing the WSL platform (no Linux distro yet)...'
wsl --install --no-distribution
Write-Host ''
Write-Host 'Fetching the latest WSL update...'
wsl --update
wsl --set-default-version 2
Write-Host ''
Write-Host 'If you see a message above about a RESTART being required,'
Write-Host 'restart Windows now, then run the WSL Control Panel again.'
Write-Host ''
Write-Host 'Press any key to close this window...'
$null = [Console]::ReadKey($true)
'@
    Write-Host "`n Asking for administrator rights - please click YES on the prompt..." -ForegroundColor Cyan
    if (-not (Invoke-ElevatedScript $setup)) {
        Write-Host ' The administrator prompt was declined or failed.' -ForegroundColor Red
    }

    Write-Host "`n Checking whether WSL is ready..." -ForegroundColor Cyan
    $state = 'READY'
    if (-not (Test-WslFiles)) { $state = 'MISSING' }
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { $state = 'RESTART' }
    if ($state -eq 'READY' -and (Invoke-WslQuiet @('--version')).ExitCode -ne 0) { $state = 'RESTART' }

    if ($state -eq 'READY') {
        Write-Host "`n WSL is installed and ready. Use [N] in the panel to download a Linux distro." -ForegroundColor Green
        Pause-Console
        return $true
    }
    if ($state -eq 'MISSING') {
        Write-Host "`n WSL did not get installed. This happens if you clicked NO on the" -ForegroundColor Red
        Write-Host ' security prompt, or the administrator window showed an error (for'
        Write-Host ' example no internet). Run this panel again to retry.'
    } else {
        Write-Host "`n WSL was set up but Windows needs a RESTART to finish enabling it." -ForegroundColor Yellow
        Write-Host '   1. Restart your PC.'
        Write-Host '   2. Run this WSL Control Panel again.'
        Write-Host '   3. Use [N] to download your first Linux distro.'
    }
    Pause-Console
    return $false
}

# ------------------------------------------------------------------------------
# Saved accounts (username + DPAPI-encrypted password, one file per distro)
# ------------------------------------------------------------------------------
function Get-AccountFile([string]$distro) { return (Join-Path $ACCOUNTS_FOLDER "$distro.acct") }
function Get-PortFile([string]$distro)    { return (Join-Path $ACCOUNTS_FOLDER "$distro.port") }

function Get-DistroPort([string]$distro) {
    $f = Get-PortFile $distro
    if (Test-Path -LiteralPath $f) {
        $p = (Get-Content -LiteralPath $f -Raw).Trim()
        if ($p -match '^\d+$') { return [int]$p }
    }
    return [int]$Global:Config.DefaultRdpPort
}

function Set-DistroPort([string]$distro, [int]$port) {
    if (-not (Test-Path -LiteralPath $ACCOUNTS_FOLDER)) { New-Item -ItemType Directory -Path $ACCOUNTS_FOLDER -Force | Out-Null }
    Set-Content -LiteralPath (Get-PortFile $distro) -Value $port -Force
}

# Why <port> cannot be used for <distro>'s xrdp, or $null if it is free.
function Get-PortProblem([string]$distro, [int]$port) {
    if ($port -eq 3389) { return "Port 3389 belongs to Windows' own Remote Desktop." }
    foreach ($d in @(Get-WslDistros | Where-Object { -not $_.IsSystem -and $_.Name -ne $distro })) {
        if ((Get-DistroPort $d.Name) -eq $port) { return "'$($d.Name)' is already set to use port $port." }
    }
    # Something on Windows already listening (skipped for this distro's current
    # port: its own running xrdp shows up there).
    if ($port -ne (Get-DistroPort $distro)) {
        try {
            if (Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction Stop) {
                return "Another program on Windows is already listening on port $port."
            }
        } catch { }
    }
    return $null
}

function Get-SavedAccounts([string]$distro) {
    $file = Get-AccountFile $distro
    $accounts = @()
    if (Test-Path -LiteralPath $file) {
        foreach ($line in (Get-Content -LiteralPath $file)) {
            $parts = $line.Split(',')
            if ($parts.Count -ge 2 -and $parts[0].Trim() -and $parts[1].Trim()) {
                $accounts += [PSCustomObject]@{ Username = $parts[0].Trim(); EncryptedBlob = $parts[1].Trim() }
            }
        }
    }
    return $accounts
}

function Save-EncryptedAccount([string]$distro, [string]$username, [string]$password) {
    Add-Type -AssemblyName System.Security
    $bytes = [System.Text.Encoding]::Unicode.GetBytes($password)
    $enc = [System.Security.Cryptography.ProtectedData]::Protect($bytes, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
    $hex = (($enc | ForEach-Object { $_.ToString('x2') }) -join '')
    if (-not (Test-Path -LiteralPath $ACCOUNTS_FOLDER)) { New-Item -ItemType Directory -Path $ACCOUNTS_FOLDER -Force | Out-Null }
    $file = Get-AccountFile $distro
    $keep = @()
    if (Test-Path -LiteralPath $file) { $keep = @(Get-Content -LiteralPath $file | Where-Object { $_ -and -not $_.StartsWith("$username,") }) }
    Set-Content -LiteralPath $file -Value ($keep + "$username,$hex") -Force
}

function Remove-SavedAccount([string]$distro, [string]$username) {
    $file = Get-AccountFile $distro
    if (Test-Path -LiteralPath $file) {
        $keep = @(Get-Content -LiteralPath $file | Where-Object { $_ -and -not $_.StartsWith("$username,") })
        if ($keep.Count -eq 0) { Remove-Item -LiteralPath $file -Force } else { Set-Content -LiteralPath $file -Value $keep -Force }
    }
}

function Test-LinuxUserExists([string]$distro, [string]$user) {
    return ((Invoke-WslQuiet @('-d', $distro, '-u', 'root', '-e', 'id', '-u', $user)).ExitCode -eq 0)
}

# Sets <user>'s Linux password. The password goes in over stdin: it never lands
# on disk or on a command line.
function Set-LinuxPassword([string]$distro, [string]$user, [string]$password) {
    # bash gives a PATH that includes /usr/sbin (plain "-e chpasswd" cannot find it).
    # sed strips a byte-order mark / CR the stdin pipe may add - left in, they
    # corrupt the user name and the password.
    $cmd = 'sed -e ''s/^\xef\xbb\xbf//'' -e ''s/\r$//'' | chpasswd'
    $res = Invoke-WslQuiet @('-d', $distro, '-u', 'root', '-e', 'bash', '-c', $cmd) "${user}:${password}`n"
    return ($res.ExitCode -eq 0)
}

# Creates (or updates) the Linux user inside the distro: sudo/wheel rights and
# an XFCE session file, then sets the password. Returns $true on success.
function New-LinuxUser([string]$distro, [string]$user, [string]$password) {
    Write-Host "`n Creating user '$user' inside $distro - please wait, this can take a minute or two..." -ForegroundColor Cyan
    $res = Invoke-WslScript $distro 'root' (Get-ScriptText 'create-user.sh') @($user)
    foreach ($l in $res.Output) { Write-Host "   $l" -ForegroundColor DarkGray }
    if ($res.ExitCode -ne 0) {
        Write-Host " The user could not be created (exit code $($res.ExitCode))." -ForegroundColor Red
        return $false
    }
    Write-Host '   - setting the password...' -ForegroundColor DarkGray
    if (-not (Set-LinuxPassword $distro $user $password)) {
        Write-Host ' Could not set the user/password in the distro.' -ForegroundColor Red
        return $false
    }
    Write-Host ' Done - the Linux account is ready.' -ForegroundColor Green
    return $true
}

function Read-NewPassword([string]$who, [string]$what = 'password') {
    $p1 = Read-Secret " Enter $what for '$who'"
    $p2 = Read-Secret ' Confirm password'
    if ($p1 -ne $p2) { Write-Host ' The two passwords did not match - nothing saved.' -ForegroundColor Red; return $null }
    if (-not $p1)    { Write-Host ' The password cannot be empty.' -ForegroundColor Red; return $null }
    return $p1
}

# Add (or re-create) one account. $createInLinux = also make the Linux user.
function Add-AccountInteractive([string]$distro, [string]$uname, [bool]$createInLinux) {
    Write-Host ''
    if ($createInLinux) {
        Write-Host " Enter a password for '$uname' - you type it twice."
        Write-Host ' It becomes the Linux login password AND is saved here, encrypted.'
    } else {
        Write-Host " Enter the EXISTING Linux password for '$uname' - typed twice."
        Write-Host ' It is only saved here, encrypted; the distro is not changed.'
    }
    $pw = Read-NewPassword $uname
    if ($null -eq $pw) { return $false }
    if ($createInLinux -and -not (New-LinuxUser $distro $uname $pw)) {
        Write-Host ' Nothing saved. Open the distro as a Terminal to check it is healthy, then try again.' -ForegroundColor Yellow
        return $false
    }
    Save-EncryptedAccount $distro $uname $pw
    Write-Host "`n Account '$uname' saved for $distro (encrypted with Windows DPAPI)." -ForegroundColor Green
    if (-not $createInLinux) { Write-Host ' NOTE: this did NOT create the Linux user - it only remembers the login.' -ForegroundColor Yellow }
    return $true
}

# A saved account is only a remembered login; the Linux user lives INSIDE the
# distro. If the distro was deleted and downloaded again, the saved login still
# shows up but the user is gone and every open fails ("User not found"). Returns
# $true when the account can be used (existing, or re-created now).
function Confirm-AccountExists([string]$distro, $account) {
    if (-not $account) { return $true }
    if (Test-LinuxUserExists $distro $account.Username) { return $true }
    Write-Host ''
    Write-Host " The saved account '$($account.Username)' does NOT exist inside $distro." -ForegroundColor Yellow
    Write-Host ' (Usually because the distro was deleted and downloaded again - a fresh'
    Write-Host '  distro only has "root".) The panel can create it again now.'
    Write-Host ''
    if (-not (Read-YesNo "Create Linux user '$($account.Username)' inside $distro now?" $true)) { return $false }
    return (Add-AccountInteractive $distro $account.Username $true)
}

function Show-AccountMenu([string]$distro) {
    while ($true) {
        Show-Header "Manage Accounts for: $distro"
        $accounts = @(Get-SavedAccounts $distro)
        Write-Host ' Saved accounts (used for auto-login):' -ForegroundColor Yellow
        if ($accounts.Count -eq 0) { Write-Host '   (none saved yet)' -ForegroundColor DarkGray }
        for ($i = 0; $i -lt $accounts.Count; $i++) { Write-Host "   [$($i + 1)] $($accounts[$i].Username)" }
        Write-Host ''
        Write-Host '   [A] Add an account       - save a login and (for a fresh distro) CREATE the Linux user'
        Write-Host '   [P] Change a password    - changes it in Linux AND in the panel'
        Write-Host '   [R] Remove a saved account'
        Write-Host '   [B] Back'
        Write-Host ''
        $opt = (Read-Line ' Enter your choice').ToUpper()

        if ($opt -eq 'B') { return }
        elseif ($opt -eq 'A') {
            Write-Host ''
            $uname = Read-Line ' Enter the Linux username'
            if ($uname -notmatch '^[a-z_][a-z0-9_-]{0,31}$') {
                Write-Host ' Invalid username: use lowercase letters, digits, - and _, starting with a letter.' -ForegroundColor Red
                Pause-Console; continue
            }
            Write-Host ''
            Write-Host " Also CREATE this user inside $distro now?"
            Write-Host '   [Y] Yes - fresh distro / new user. Makes the Linux user, gives it sudo'
            Write-Host '       (admin) and sets up the XFCE desktop session.'
            Write-Host '   [N] No  - the Linux user already exists; only remember it here.'
            $mk = Read-YesNo 'Create the Linux user too?' $true
            try { [void](Add-AccountInteractive $distro $uname $mk) }
            catch [System.IO.EndOfStreamException] { throw }
            catch { Write-Host " Error: $_" -ForegroundColor Red }
            Pause-Console
        }
        elseif ($opt -eq 'P' -or $opt -eq 'R') {
            if ($accounts.Count -eq 0) { Write-Host ' No accounts saved yet.' -ForegroundColor Yellow; Pause-Console; continue }
            $idx = Read-Line ' Enter the account number'
            $i = Get-ListIndex $idx $accounts.Count
            if ($i -lt 0) { continue }
            $target = $accounts[$i].Username
            if ($opt -eq 'R') {
                Remove-SavedAccount $distro $target
                Write-Host " Removed saved account '$target' (the Linux user is untouched)." -ForegroundColor Green
            } else {
                Write-Host ''
                $pw = Read-NewPassword $target 'the NEW password'
                if ($null -ne $pw) {
                    if (Set-LinuxPassword $distro $target $pw) {
                        Save-EncryptedAccount $distro $target $pw
                        Write-Host ' Password updated in Linux and in the panel.' -ForegroundColor Green
                    } else {
                        Write-Host " Linux refused the change (does '$target' exist inside $distro?). Nothing saved." -ForegroundColor Red
                    }
                }
            }
            Pause-Console
        }
    }
}

# ------------------------------------------------------------------------------
# Desktop and terminal launching
# ------------------------------------------------------------------------------
# Keeps the WSL VM awake while the XFCE desktop is in use (otherwise WSL
# idle-shuts-down seconds after this launcher exits). The helper exits at logout.
function Start-KeepAlive([string]$distro) {
    $b64 = ConvertTo-Base64 (Get-ScriptText 'keepalive.sh')
    $cmd = "echo '$b64' | base64 -d > /usr/local/bin/xrdp-keepalive.sh && chmod +x /usr/local/bin/xrdp-keepalive.sh"
    Invoke-WslQuiet @('-d', $distro, '-u', 'root', '-e', 'bash', '-c', $cmd) | Out-Null
    Start-Process -FilePath (Get-WslExe) -WindowStyle Hidden `
        -ArgumentList (Join-WinArgs @('-d', $distro, '-u', 'root', '--', '/usr/local/bin/xrdp-keepalive.sh'))
}

# Installs the XFCE desktop (+ xrdp, or Kali's Win-KeX). Returns $true on success.
function Install-DesktopInDistro([string]$distro, [int]$port, [bool]$isKali) {
    Show-Header "Installing a desktop for: $distro"
    # Output goes to the screen AND (through tee) to a log inside the distro,
    # which is copied to data\logs afterwards so a failure can still be read.
    $log = '/var/log/wsl-panel-desktop-install.log'
    if ($isKali) {
        Write-Host " Installing Kali's XFCE desktop + Win-KeX (about 1-2 GB - this can take a while)..." -ForegroundColor Yellow
        $cmd = '{ set -e; export DEBIAN_FRONTEND=noninteractive; apt-get update && apt-get install -y kali-desktop-xfce dbus-x11 kali-win-kex; } 2>&1 | tee ' + $log + '; exit ${PIPESTATUS[0]}'
        $rc = Invoke-WslInline @('-d', $distro, '-u', 'root', '--', 'bash', '-lc', $cmd)
    } else {
        Write-Host " Installing an XFCE desktop + xrdp (port $port) on $distro ..." -ForegroundColor Yellow
        Write-Host ' (auto-detecting the package manager - this can take several minutes)' -ForegroundColor DarkGray
        Write-Host ''
        # The installer is streamed in through stdin from a temp file (like the
        # old .bat did) so no command line has to carry it.
        $tmp = Join-Path $env:TEMP 'wsl-desktop-setup.b64'
        Set-Content -LiteralPath $tmp -Value (ConvertTo-Base64 (Get-ScriptText 'install-desktop.sh')) -Force -Encoding Ascii
        $cmd = "tr -d '\r' | base64 -d > /tmp/wsl-desktop-setup.sh && { bash /tmp/wsl-desktop-setup.sh $port </dev/null 2>&1 | tee $log; rc=`${PIPESTATUS[0]}; rm -f /tmp/wsl-desktop-setup.sh; exit `$rc; }"
        $rc = Invoke-WslInline @('-d', $distro, '-u', 'root', '-e', 'bash', '-c', $cmd) $tmp
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
    $saved = Save-DistroLog $distro $log 'desktop-install'
    if ($rc -eq 0) {
        Write-Host "`n Desktop installation finished." -ForegroundColor Green
        Start-Sleep -Seconds 2
        return $true
    }
    Write-Host "`n The desktop install did not complete (exit code $rc). Common causes:" -ForegroundColor Red
    Write-Host '   - no internet connection inside the distro'
    Write-Host '   - the package manager is locked by another update running now'
    Write-Host '   - out of disk space'
    Write-Host '   - Arch: building xrdp from the AUR failed (prints AUR_BUILD_FAILED above)'
    Write-Host '   - an unrecognised package manager (prints UNKNOWN_PKG_MANAGER above)'
    if ($saved) { Write-Host " The full output is saved in: $saved" -ForegroundColor Yellow }
    else { Write-Host ' Open the distro as a Terminal to read the output above, then try again.' }
    Pause-Console
    return $false
}

# Copies a log file from inside the distro to data\logs\<distro>-<what>-<time>.log.
# Returns the Windows path, or $null if there was nothing to copy.
function Save-DistroLog([string]$distro, [string]$linuxPath, [string]$what) {
    try {
        $res = Invoke-WslQuiet @('-d', $distro, '-u', 'root', '-e', 'cat', $linuxPath)
        if ($res.ExitCode -ne 0 -or $res.Output.Count -eq 0) { return $null }
        if (-not (Test-Path -LiteralPath $LOGS_FOLDER)) { New-Item -ItemType Directory -Path $LOGS_FOLDER -Force | Out-Null }
        $file = Join-Path $LOGS_FOLDER ("{0}-{1}-{2}.log" -f $distro, $what, (Get-Date -Format 'yyyy-MM-dd_HHmmss'))
        [System.IO.File]::WriteAllLines($file, [string[]]$res.Output, (New-Object System.Text.UTF8Encoding($false)))
        return $file
    } catch { return $null }
}

function Start-KexDesktop([string]$distro, $account) {
    # Win-KeX must run as a NON-root user.
    $userArgs = @()
    if ($account -and $account.Username) {
        $userArgs = @('-u', $account.Username)
    } else {
        $uid = Invoke-WslQuiet @('-d', $distro, '-e', 'id', '-u')
        if ($uid.Output.Count -gt 0 -and $uid.Output[0] -eq '0') {
            Write-Host ''
            Write-Host " The Kali desktop (Win-KeX) cannot run as root, and $distro has no normal" -ForegroundColor Red
            Write-Host ' user as its default login yet. Fix: Manage Accounts -> [A] Add an account'
            Write-Host ' (answer Y), then open the Desktop using that account.'
            Pause-Console
            return
        }
    }
    Write-Host " Starting the Kali (Win-KeX) desktop for $distro ..." -ForegroundColor Green
    Write-Host ''
    Write-Host ' A console window will open:'
    Write-Host '   - FIRST time only: it asks for a one-time Win-KeX password (local only).'
    Write-Host '     Type it twice, then answer "n" to the view-only question.'
    Write-Host '   - Every time after: it just opens the desktop.'
    Write-Host ' Closing that console does NOT close the desktop.'
    Start-KeepAlive $distro
    # cd ~ avoids the "started from a Windows dir" passwd-file failure; the visible
    # console gives the first-run password prompt a terminal; systemctl
    # set-environment stops XFCE helpers (e.g. notification daemon) falling back
    # to WSLg and popping an error window on Windows.
    $kexCmd = "cd ~ && unset WAYLAND_DISPLAY && { systemctl --user set-environment DISPLAY=:1 GDK_BACKEND=x11 XDG_SESSION_TYPE=x11 2>/dev/null; kex --win; }; echo; read -rp 'Desktop is in its own window. Press Enter to close this console. '"
    Start-Process -FilePath (Get-WslExe) -ArgumentList (Join-WinArgs (@('-d', $distro) + $userArgs + @('--', 'bash', '-lc', $kexCmd)))
    Write-Host "`n If nothing appears, read the console window for the error." -ForegroundColor DarkGray
    Pause-Console
}

function Test-XrdpListening([string]$distro, [int]$port) {
    # "-p" shows the owning program, and only for THIS distro's own processes,
    # so a listener belonging to another distro does not count as ours.
    $cmd = "ss -lntp 2>/dev/null | grep ':$port ' | grep -q xrdp"
    return ((Invoke-WslQuiet @('-d', $distro, '-u', 'root', '-e', 'sh', '-c', $cmd)).ExitCode -eq 0)
}

function Start-DistroDesktop([string]$distro, $account, [bool]$afterInstall = $false) {
    Show-Header "Opening Desktop for $distro"
    if (-not (Confirm-AccountExists $distro $account)) { return }

    Write-Host " Detecting desktop type for $distro ..." -ForegroundColor DarkGray
    # kex alone is not enough: on a minimal Kali, kali-win-kex installs without
    # the XFCE it runs, and the VNC server starts, finds no desktop and exits.
    $hasKex  = ((Invoke-WslQuiet @('-d', $distro, '--', 'bash', '-lc', 'command -v kex >/dev/null 2>&1')).ExitCode -eq 0)
    $hasXfce = $hasKex -and ((Invoke-WslQuiet @('-d', $distro, '--', 'bash', '-lc', 'command -v startxfce4 >/dev/null 2>&1')).ExitCode -eq 0)
    if ($hasKex -and $hasXfce) { Start-KexDesktop $distro $account; return }

    $port = Get-DistroPort $distro
    $isKali = Test-KaliDistro $distro
    $needInstall = $isKali
    if (-not $needInstall) {
        # All WSL2 distros share ONE network: if another running distro's xrdp
        # already holds this port, Remote Desktop would open THAT desktop instead.
        $conflict = $null
        foreach ($rd in (Get-RunningDistros)) {
            if ($rd -ne $distro -and (Test-XrdpListening $rd $port)) { $conflict = $rd; break }
        }
        if ($conflict) {
            Write-Host "`n '$conflict' is running its own desktop on port $port. WSL distros share one" -ForegroundColor Yellow
            Write-Host ' network, so two desktops cannot use the same port.'
            Write-Host "   [1] Give $distro a different free port (keeps both desktops open)"
            Write-Host "   [2] Close '$conflict' now (its desktop session ends - save work first)"
            Write-Host '   [C] Cancel'
            $ch = (Read-Line ' Choice [1]').ToUpper()
            if ($ch -eq '2') {
                Write-Host " Closing $conflict ..." -ForegroundColor Yellow
                Stop-Distro $conflict
            } elseif ($ch -eq '' -or $ch -eq '1') {
                $busy = @{}
                foreach ($rd in (Get-RunningDistros)) {
                    $res = Invoke-WslQuiet @('-d', $rd, '-u', 'root', '-e', 'sh', '-c', "ss -lnt 2>/dev/null | awk 'NR>1{n=split(`$4,a,`":`"); print a[n]}'")
                    foreach ($l in $res.Output) { $busy[$l.Trim()] = $true }
                }
                $np = $port + 1
                while ($busy.ContainsKey([string]$np)) { $np++ }
                Set-DistroPort $distro $np
                $port = $np
                Write-Host " $distro will use port $port from now on." -ForegroundColor Green
            } else { return }
        }

        Write-Host " Waking $distro and starting the desktop server (xrdp, port $port)..." -ForegroundColor Cyan
        # Point xrdp at our port (only the [Globals] "port=<digits>" line - the
        # Xorg/Xvnc sections have "port=-1" which must stay). A port change needs a
        # restart; otherwise "start" keeps any desktop session that is still open.
        $startScript = "PORT=$port`n" + @'
CHANGED=0
if [ -f /etc/xrdp/xrdp.ini ] && ! grep -Eq "^port=$PORT[[:space:]]*$" /etc/xrdp/xrdp.ini; then
    sed -i -E "/^\[Globals\]/,/^\[/ s/^port=[0-9]+[[:space:]]*$/port=$PORT/" /etc/xrdp/xrdp.ini
    CHANGED=1
fi
ACT=start; [ "$CHANGED" = 1 ] && ACT=restart
if service xrdp $ACT >/dev/null 2>&1; then :
elif systemctl $ACT xrdp >/dev/null 2>&1; then systemctl $ACT xrdp-sesman >/dev/null 2>&1
else
    if [ "$CHANGED" = 1 ]; then pkill -x xrdp >/dev/null 2>&1; pkill -x xrdp-sesman >/dev/null 2>&1; sleep 1; fi
    pgrep -x xrdp-sesman >/dev/null 2>&1 || (/usr/sbin/xrdp-sesman >/dev/null 2>&1 &)
    sleep 1
    pgrep -x xrdp >/dev/null 2>&1 || (/usr/sbin/xrdp >/dev/null 2>&1 &)
fi
'@
        Invoke-WslScript $distro 'root' $startScript | Out-Null
        Start-Sleep -Seconds 2
        if (Test-XrdpListening $distro $port) {
            Open-RemoteDesktop $distro $account $port
            return
        }
        $needInstall = $true
    }

    # No desktop server found: offer to install one.
    if ($afterInstall) {
        Write-Host "`n The desktop was installed but is still not reachable on port $port." -ForegroundColor Red
        Write-Host ' Open the distro as a Terminal and check the xrdp service, then try again.'
        Pause-Console
        return
    }
    Write-Host ''
    Write-Host ' This distro has no desktop server the panel knows how to open.' -ForegroundColor Yellow
    Write-Host ' Most distros open via xrdp; Kali opens via Win-KeX. I can download and install one now'
    Write-Host ' (needs internet and a few hundred MB; it can take several minutes).'
    Write-Host ''
    Write-Host '   [I] Install the desktop now (auto)'
    Write-Host '   [T] Open as a Terminal instead'
    Write-Host '   [B] Back'
    $nd = (Read-Line ' Enter your choice').ToUpper()
    if ($nd -eq 'T') { Start-DistroTerminal $distro $account }
    elseif ($nd -eq 'I') {
        if (Install-DesktopInDistro $distro $port $isKali) { Start-DistroDesktop $distro $account $true }
    }
}

function Open-RemoteDesktop([string]$distro, $account, [int]$port) {
    $rdp = Join-Path $env:TEMP "wsl-desktop-$distro.rdp"
    $lines = @(
        "full address:s:localhost:$port", 'screen mode id:i:2', 'dynamic resolution:i:1',
        'smart sizing:i:1', 'authentication level:i:0', 'prompt for credentials:i:0'
    )
    if ($account) {
        $lines += "username:s:$($account.Username)"
        $lines += "password 51:b:$($account.EncryptedBlob)"
    }
    Set-Content -LiteralPath $rdp -Value $lines -Force
    Start-KeepAlive $distro
    Write-Host ' Opening Windows Remote Desktop (mstsc)...' -ForegroundColor Green
    Start-Process -FilePath 'mstsc.exe' -ArgumentList (Join-WinArgs @($rdp))
    # The .rdp file holds the encrypted login: delete it once mstsc has read it.
    Start-Sleep -Seconds 5
    Remove-Item -LiteralPath $rdp -Force -ErrorAction SilentlyContinue
    if (-not $account) { Write-Host ' Log in with your Linux username and password.' -ForegroundColor Yellow }
    Pause-Console
}

function Start-DistroTerminal([string]$distro, $account) {
    Write-Host "`n Opening a terminal window for $distro ..." -ForegroundColor Cyan
    $a = @('-d', $distro)
    if ($account -and $account.Username) { $a += @('-u', $account.Username) }
    $wt = Get-Command wt.exe -ErrorAction SilentlyContinue
    if ($wt) { Start-Process -FilePath $wt.Source -ArgumentList (Join-WinArgs (@('wsl.exe') + $a)) }
    else     { Start-Process -FilePath (Get-WslExe) -ArgumentList (Join-WinArgs $a) }
}

# ------------------------------------------------------------------------------
# Disk compaction
# ------------------------------------------------------------------------------
function Compact-DistroDisk([string]$distro) {
    Show-Header "Compact the virtual hard disk: $distro"
    $vhd = Get-DistroVhdInfo $distro
    if (-not $vhd.Exists) {
        Write-Host " Could not find ext4.vhdx for $distro." -ForegroundColor Red
        Pause-Console; return
    }
    Write-Host " Disk file:     $($vhd.VhdxPath)"
    Write-Host " Current size:  $($vhd.SizeGB) GB" -ForegroundColor Yellow
    Write-Host ''
    Write-Host ' A WSL2 disk grows as files are added but never shrinks when you delete'
    Write-Host ' files inside Linux. Compacting hands that unused space back to Windows.'
    Write-Host ' This stops ALL WSL distros (wsl --shutdown) and needs administrator rights.'
    Write-Host ''
    Write-Host '   [1] Compact now (recommended)'
    Write-Host '   [2] Turn on sparse mode (automatic, but disabled by newer WSL versions)'
    Write-Host '   [B] Back'
    $m = (Read-Line ' Choose [1]').ToUpper()
    if ($m -eq 'B') { return }

    Write-Host "`n Shutting WSL down so the disk file is free..." -ForegroundColor Yellow
    Stop-KexAll
    Invoke-WslQuiet @('--shutdown') | Out-Null
    Start-Sleep -Seconds 3

    if ($m -eq '2') {
        $res = Invoke-WslQuiet @('--manage', $distro, '--set-sparse', 'true')
        if ($res.ExitCode -eq 0) {
            Write-Host ' Sparse mode enabled - WSL will now reclaim free space by itself.' -ForegroundColor Green
            Pause-Console; return
        }
        Write-Host ' This WSL version refused sparse mode - compacting instead.' -ForegroundColor Yellow
    }

    # diskpart reads its commands from a pipe, so no script file is written.
    $vhdArg = $vhd.VhdxPath -replace "'", "''"
    $compact = "@('select vdisk file=`"$vhdArg`"', 'attach vdisk readonly', 'compact vdisk', 'detach vdisk', 'exit') | diskpart.exe"
    Write-Host ' Compacting with diskpart (a Windows security prompt may appear - click YES)...' -ForegroundColor Cyan
    if (Test-IsAdmin) {
        @("select vdisk file=`"$($vhd.VhdxPath)`"", 'attach vdisk readonly', 'compact vdisk', 'detach vdisk', 'exit') | diskpart.exe | Out-Host
    } elseif (-not (Invoke-ElevatedScript $compact)) {
        Write-Host ' The administrator prompt was declined or failed - nothing was changed.' -ForegroundColor Red
        Pause-Console; return
    }

    $after = Get-DistroVhdInfo $distro
    $saved = [math]::Round($vhd.SizeGB - $after.SizeGB, 2)
    Write-Host ''
    Write-Host " Size now: $($after.SizeGB) GB (was $($vhd.SizeGB) GB)" -ForegroundColor Green
    if ($saved -gt 0) { Write-Host " Reclaimed $saved GB of disk space." -ForegroundColor Green }
    else { Write-Host ' Nothing more could be reclaimed (or the compaction did not run).' -ForegroundColor Yellow }
    Pause-Console
}

# ------------------------------------------------------------------------------
# systemd toggle
# ------------------------------------------------------------------------------
function Toggle-DistroSystemd([string]$distro) {
    Show-Header "systemd: $distro"
    $chk = Invoke-WslQuiet @('-d', $distro, '-u', 'root', '-e', 'sh', '-c', "grep -Eq '^[[:space:]]*systemd[[:space:]]*=[[:space:]]*true' /etc/wsl.conf 2>/dev/null && echo ENABLED || echo DISABLED")
    $enabled = ($chk.Output.Count -gt 0 -and $chk.Output[0] -eq 'ENABLED')
    Write-Host " systemd is currently: $(if ($enabled) { 'ENABLED' } else { 'DISABLED' })" -ForegroundColor Yellow
    Write-Host ''
    Write-Host ' systemd is the standard Linux service manager. With it on, services (Docker,'
    Write-Host ' SSH, cron, databases) start properly. It is set in /etc/wsl.conf and takes'
    Write-Host ' effect after the distro restarts.'
    Write-Host ''
    if (-not (Read-YesNo "$(if ($enabled) { 'Turn it OFF' } else { 'Turn it ON' })?" $true)) { return }

    if ($enabled) {
        $s = "sed -i -E 's/^([[:space:]]*systemd[[:space:]]*=).*/\1false/' /etc/wsl.conf"
    } else {
        $s = @'
touch /etc/wsl.conf
if grep -Eq '^[[:space:]]*systemd[[:space:]]*=' /etc/wsl.conf; then
    sed -i -E 's/^([[:space:]]*systemd[[:space:]]*=).*/\1true/' /etc/wsl.conf
elif grep -q '^\[boot\]' /etc/wsl.conf; then
    sed -i '/^\[boot\]/a systemd=true' /etc/wsl.conf
else
    printf '\n[boot]\nsystemd=true\n' >> /etc/wsl.conf
fi
'@
    }
    $res = Invoke-WslScript $distro 'root' $s
    if ($res.ExitCode -ne 0) { Write-Host ' Could not edit /etc/wsl.conf.' -ForegroundColor Red; Pause-Console; return }
    Stop-Distro $distro
    Write-Host " Done. $distro was stopped - systemd is $(if ($enabled) { 'off' } else { 'on' }) the next time it starts." -ForegroundColor Green
    Pause-Console
}

# ------------------------------------------------------------------------------
# Distro menu
# ------------------------------------------------------------------------------
function Show-OpenMenu([string]$distro) {
    Show-Header "Open: $distro"
    $accounts = @(Get-SavedAccounts $distro)
    $account = $null
    if ($accounts.Count -gt 0) {
        Write-Host ' Choose an account:' -ForegroundColor Yellow
        for ($i = 0; $i -lt $accounts.Count; $i++) { Write-Host "   [$($i + 1)] $($accounts[$i].Username)" }
        Write-Host '   [N] Open WITHOUT a saved account (you type your login yourself)'
        Write-Host '   [B] Back'
        Write-Host ''
        $ch = (Read-Line ' Select [1]').ToUpper()
        if ($ch -eq 'B') { return }
        if ($ch -eq '') { $ch = '1' }
        $i = Get-ListIndex $ch $accounts.Count
        if ($i -ge 0) { $account = $accounts[$i] }
        elseif ($ch -ne 'N') { Write-Host ' Not a valid choice.' -ForegroundColor Red; Pause-Console; return }
    } else {
        Write-Host ' No saved account yet. Use Manage Accounts -> [A] to create one (needed for' -ForegroundColor DarkGray
        Write-Host ' a fresh distro, which only has "root").' -ForegroundColor DarkGray
    }

    Write-Host ''
    Write-Host '   [1] Desktop  - full XFCE desktop (Kali: Win-KeX window; others: Remote Desktop)'
    Write-Host '   [2] Terminal - command-line window (fastest; no desktop needed)'
    Write-Host '   [B] Back'
    Write-Host ''
    $m = (Read-Line ' Enter your choice [1]').ToUpper()
    if ($m -eq '' -or $m -eq '1') { Start-DistroDesktop $distro $account }
    elseif ($m -eq '2') {
        if (Confirm-AccountExists $distro $account) { Start-DistroTerminal $distro $account }
    }
}

function Show-DistroMenu([string]$distro) {
    while ($true) {
        $cur = Get-WslDistros | Where-Object { $_.Name -eq $distro } | Select-Object -First 1
        if (-not $cur) { return }
        $running = ($cur.State -eq 'Running')
        $vhd = Get-DistroVhdInfo $distro
        Show-Header "Manage: $distro"
        Write-Host ' State:      ' -NoNewline
        if ($running) { Write-Host 'RUNNING' -ForegroundColor Green } else { Write-Host $cur.State.ToUpper() -ForegroundColor DarkGray }
        Write-Host " Disk size:  $($vhd.SizeGB) GB"
        Write-Host " xrdp port:  $(Get-DistroPort $distro)"
        Write-Host '----------------------------------------------------------------' -ForegroundColor DarkGray
        Write-Host ''
        Write-Host '   [O] Open            - pick an account, then Desktop or Terminal'
        if ($running) { Write-Host '   [C] Close           - "wsl --terminate", frees its RAM' }
        Write-Host '   [A] Accounts        - add, change password, remove saved logins'
        Write-Host '   [P] xrdp port       - change the Remote Desktop port for this distro'
        Write-Host '   [K] Compact disk    - give unused ext4.vhdx space back to Windows'
        Write-Host '   [Y] systemd         - turn systemd on/off in /etc/wsl.conf'
        Write-Host '   [D] Delete          - "wsl --unregister" - ERASES it (permanent!)'
        Write-Host '   [B] Back'
        Write-Host ''
        $opt = (Read-Line ' Enter your choice').ToUpper()

        if ($opt -eq 'B') { return }
        elseif ($opt -eq 'O') { Show-OpenMenu $distro }
        elseif ($opt -eq 'C' -and $running) {
            Write-Host "`n Shutting down $distro ..." -ForegroundColor Yellow
            Stop-Distro $distro
            Free-WslVm
            Write-Host " Done - $distro is stopped." -ForegroundColor Green
            Pause-Console
        }
        elseif ($opt -eq 'A') { Show-AccountMenu $distro }
        elseif ($opt -eq 'P') {
            $np = Read-Line ' New xrdp port (1024-65535, e.g. 3391)'
            if ($np -match '^\d{1,5}$' -and [int]$np -ge 1024 -and [int]$np -le 65535) {
                $problem = Get-PortProblem $distro ([int]$np)
                if ($problem) {
                    Write-Host " $problem Pick another port." -ForegroundColor Red
                } else {
                    Set-DistroPort $distro ([int]$np)
                    Write-Host " Port set to $np. It is applied the next time you open the desktop." -ForegroundColor Green
                }
            } else { Write-Host ' Not a valid port.' -ForegroundColor Red }
            Pause-Console
        }
        elseif ($opt -eq 'K') { Compact-DistroDisk $distro }
        elseif ($opt -eq 'Y') { Toggle-DistroSystemd $distro }
        elseif ($opt -eq 'D') {
            Write-Host ''
            Write-Host " WARNING: this permanently erases '$distro' and ALL of its files." -ForegroundColor Red
            $conf = Read-Line " Type the distro name exactly to confirm ($distro)"
            if ($conf -ceq $distro) {
                Write-Host "`n Deleting $distro ..." -ForegroundColor Yellow
                Invoke-WslQuiet @('--unregister', $distro) | Out-Null
                # Saved accounts and the port belong to the deleted distro.
                Remove-Item -LiteralPath (Get-AccountFile $distro) -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath (Get-PortFile $distro) -Force -ErrorAction SilentlyContinue
                Write-Host " Done - $distro was deleted." -ForegroundColor Green
                Pause-Console
                return
            }
            Write-Host ' Cancelled - nothing was deleted.' -ForegroundColor DarkGray
            Pause-Console
        }
    }
}

# ------------------------------------------------------------------------------
# Backup / restore
# ------------------------------------------------------------------------------
function Export-DistroMenu {
    Show-Header 'Back up a distro (wsl --export)'
    $distros = @(Get-WslDistros | Where-Object { -not $_.IsSystem })
    if ($distros.Count -eq 0) { Write-Host ' No distros installed - nothing to back up.' -ForegroundColor DarkGray; Pause-Console; return }

    Write-Host ' Which distro should be backed up?' -ForegroundColor Yellow
    for ($i = 0; $i -lt $distros.Count; $i++) { Write-Host "   [$($i + 1)] $($distros[$i].Name)" }
    Write-Host '   [B] Back'
    $c = Read-Line ' Enter your choice'
    $pick = Get-ListIndex $c $distros.Count
    if ($pick -lt 0) { return }
    $name = $distros[$pick].Name

    Write-Host ''
    Write-Host '   [1] .tar  - works on any WSL machine'
    Write-Host '   [2] .vhdx - fastest, an exact copy of the disk'
    $ext = $(if ((Read-Line ' Format [1]') -eq '2') { 'vhdx' } else { 'tar' })

    $dir = Read-Folder 'Where should the backup be saved?' $Global:Config.BackupBase
    if ($null -eq $dir) { return }
    $stamp = Get-Date -Format 'yyyy-MM-dd_HHmm'
    $file = Join-Path $dir "${name}_$stamp.$ext"

    Write-Host ''
    Write-Host " This will STOP $name (an open desktop/terminal closes - save your work)," -ForegroundColor Yellow
    Write-Host " then save it all to: $file"
    if (-not (Read-YesNo 'Start the backup?' $false)) { return }

    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    if ($distros[$pick].State -eq 'Running') { Write-Host " Stopping $name ..."; Stop-Distro $name }

    Write-Host ' Exporting - please wait (can take a few minutes)...' -ForegroundColor Cyan
    $a = @('--export', $name, $file)
    if ($ext -eq 'vhdx') { $a += '--vhd' }
    $rc = Invoke-WslInline $a
    if ($rc -eq 0 -and (Test-Path -LiteralPath $file)) {
        $gb = [math]::Round((Get-Item -LiteralPath $file).Length / 1GB, 2)
        Write-Host "`n Done - backup saved ($gb GB):" -ForegroundColor Green
        Write-Host "   $file"
        Write-Host ''
        Write-Host ' NOTE: saved panel accounts are NOT in the backup (their passwords are locked'
        Write-Host ' to this Windows login). On another PC re-add them with Manage Accounts -> [A],'
        Write-Host ' answering N (the Linux user already exists inside the backup).'
    } else {
        Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
        Write-Host "`n The backup FAILED (exit code $rc). Common causes: not enough free space in" -ForegroundColor Red
        Write-Host " $dir, or that folder cannot be written to."
    }
    Free-WslVm
    Pause-Console
}

function Import-DistroMenu {
    Show-Header 'Restore a backup (wsl --import)'
    $dir = $Global:Config.BackupBase
    $files = @()
    if (Test-Path -LiteralPath $dir) {
        $files = @(Get-ChildItem -LiteralPath $dir -File | Where-Object { $_.Extension -in '.tar', '.vhdx' } | Sort-Object LastWriteTime -Descending)
    }
    Write-Host " Backups found in ${dir} (newest first):" -ForegroundColor Yellow
    if ($files.Count -eq 0) { Write-Host '   (none there)' -ForegroundColor DarkGray }
    $shown = [math]::Min(15, $files.Count)
    for ($i = 0; $i -lt $shown; $i++) {
        Write-Host "   [$($i + 1)] $($files[$i].Name)  ($([math]::Round($files[$i].Length / 1GB, 2)) GB)"
    }
    Write-Host ''
    Write-Host '   [P] Type the full path to a .tar / .vhdx file somewhere else (e.g. a USB)'
    Write-Host '   [B] Back'
    $c = Read-Line ' Enter your choice'
    if (-not $c -or $c.ToUpper() -eq 'B') { return }

    $selected = $null
    if ($c.ToUpper() -eq 'P') {
        $custom = (Read-Line ' Full path to the file').Trim('"', "'")
        if ($custom) { $selected = $custom }
    } elseif (($fi = Get-ListIndex $c $shown) -ge 0) {
        $selected = $files[$fi].FullName
    }
    if (-not $selected -or -not (Test-Path -LiteralPath $selected -PathType Leaf)) {
        Write-Host ' File not found or invalid choice.' -ForegroundColor Red; Pause-Console; return
    }

    # Suggest the original name: the file name minus the _date_time part.
    $def = [System.IO.Path]::GetFileNameWithoutExtension($selected) -replace '_\d{4}-\d{2}-\d{2}_\d{4}$', ''
    $name = Read-Line " Name for the restored distro [$def]"
    if (-not $name) { $name = $def }
    if (-not (Test-DistroName $name)) {
        Write-Host ' A distro name can only use letters, digits, dot, - and _ (no spaces).' -ForegroundColor Red
        Pause-Console; return
    }
    if (Get-WslDistros | Where-Object { $_.Name -eq $name }) {
        Write-Host " A distro called '$name' is already installed. Restore under a different" -ForegroundColor Red
        Write-Host " name (e.g. $name-restored) or delete the existing one first."
        Pause-Console; return
    }

    $loc = Read-Folder 'Where should the restored distro be installed?' (Join-Path $Global:Config.WslBase $name)
    if ($null -eq $loc) { return }
    if (Test-Path -LiteralPath (Join-Path $loc 'ext4.vhdx')) {
        Write-Host " $loc already holds a distro disk (ext4.vhdx). Pick another folder." -ForegroundColor Red
        Pause-Console; return
    }
    if (-not (Test-Path -LiteralPath $loc)) { New-Item -ItemType Directory -Path $loc -Force | Out-Null }

    Write-Host "`n Restoring $name - this can take a few minutes..." -ForegroundColor Cyan
    $a = @('--import', $name, $loc, $selected)
    if ($selected.EndsWith('.vhdx', [System.StringComparison]::OrdinalIgnoreCase)) { $a += '--vhd' }
    $rc = Invoke-WslInline $a
    if ($rc -ne 0) {
        Write-Host "`n The restore FAILED (exit code $rc). Common causes: not enough free space," -ForegroundColor Red
        Write-Host ' or the file is incomplete/damaged.'
        Pause-Console; return
    }
    Write-Host "`n Done - $name is restored with all its programs and files." -ForegroundColor Green
    # Import always starts as root: make the first regular user the default login.
    $res = Invoke-WslQuiet @('-d', $name, '-u', 'root', '-e', 'sh', '-c', "getent passwd | awk -F: '`$3>=1000 && `$3<60000 {print `$1; exit}'")
    if ($res.Output.Count -gt 0 -and $res.Output[0] -match '^[a-z_][a-z0-9_-]*$') {
        Invoke-WslQuiet @('--manage', $name, '--set-default-user', $res.Output[0]) | Out-Null
        Write-Host " Default login set to '$($res.Output[0])' (the user found inside the backup)." -ForegroundColor Green
    } else {
        Write-Host ' No normal user was found inside it, so it opens as root.' -ForegroundColor Yellow
    }
    Write-Host ' Saved panel accounts are not part of a backup: for auto-login use Manage'
    Write-Host ' Accounts -> [A] and answer N (the Linux user already exists).'
    Invoke-WslQuiet @('--terminate', $name) | Out-Null
    Free-WslVm
    Pause-Console
}

# ------------------------------------------------------------------------------
# Downloading a new distro (with a resumable fallback)
# ------------------------------------------------------------------------------
function Download-DistroMenu {
    Show-Header 'Download a NEW distro'
    Write-Host ' Distros available to install:' -ForegroundColor Yellow
    Write-Host '----------------------------------------------------------------' -ForegroundColor DarkGray
    foreach ($l in (Invoke-WslQuiet @('--list', '--online')).Output) { Write-Host " $l" }
    Write-Host '----------------------------------------------------------------' -ForegroundColor DarkGray
    Write-Host ''
    $name = Read-Line ' Type the NAME exactly as in the first column (e.g. Debian), or B to go back'
    if (-not $name -or $name.ToUpper() -eq 'B') { return }
    if (-not (Test-DistroName $name)) { Write-Host ' That is not a valid distro name.' -ForegroundColor Red; Pause-Console; return }

    $base = Read-Folder "Where should $name be installed? (its own sub-folder is created inside)" $Global:Config.WslBase
    if ($null -eq $base) { return }
    $loc = Join-Path $base $name
    if (-not (Test-Path -LiteralPath $loc)) { New-Item -ItemType Directory -Path $loc -Force | Out-Null }

    Write-Host "`n Installing $name into $loc - this downloads several hundred MB, please wait..." -ForegroundColor Cyan
    $rc = Invoke-WslInline @('--install', $name, '--location', $loc, '--no-launch')
    if ($rc -eq 0) { Show-DownloadDone; return }

    Write-Host "`n The download/install FAILED (exit code $rc). Common causes:" -ForegroundColor Yellow
    Write-Host '   - the server dropped the connection ("connection was reset"). Debian does this often.'
    Write-Host '   - the name was typed wrong, or a distro with that name is already installed'
    Write-Host ''
    Write-Host '   [Y] Try a RESUMABLE download - fetches the same official file in pieces, continues'
    Write-Host '       wherever the connection drops, checks its SHA-256 fingerprint, then installs it'
    Write-Host '   [N] Back'
    if (-not (Read-YesNo 'Try the resumable download?' $false)) { return }

    Write-Host "`n Reading Microsoft's official distro list..." -ForegroundColor Cyan
    try {
        $json = Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/microsoft/WSL/master/distributions/DistributionInfo.json'
        # Each value is an array of entries, so unroll it before filtering.
        $entry = $json.ModernDistributions.PSObject.Properties.Value | ForEach-Object { $_ } | Where-Object { $_.Name -eq $name } | Select-Object -First 1
        if (-not $entry) { Write-Host " '$name' has no downloadable image in Microsoft's list." -ForegroundColor Red; Pause-Console; return }
        $key = $(if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'Arm64Url' } else { 'Amd64Url' })
        $url = $entry.$key.Url
        $sha = ([string]$entry.$key.Sha256) -replace '^0x', ''
        # The temp name carries the start of the image's SHA-256, so curl only
        # resumes a partial file of THIS image. Leftovers of older images
        # (a newer one was published since) are deleted instead.
        $tag = $sha.Substring(0, [math]::Min(12, $sha.Length)).ToLower()
        $file = Join-Path $env:TEMP "wsl-$name-$tag.wsl"
        Get-ChildItem -LiteralPath $env:TEMP -Filter "wsl-$name-*.wsl" -File -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -ne $file } | Remove-Item -Force -ErrorAction SilentlyContinue

        Write-Host " Downloading $url" -ForegroundColor Cyan
        Write-Host ' (resumable: if the server drops the connection it continues where it stopped)' -ForegroundColor DarkGray
        $ok = $false
        for ($i = 1; $i -le 60; $i++) {
            & curl.exe -L -C - -sS --max-time 300 -o $file $url
            if ($LASTEXITCODE -eq 0) { $ok = $true; break }
            Write-Host "   connection dropped - resuming (attempt $i of 60)..." -ForegroundColor Yellow
            Start-Sleep -Seconds 2
        }
        if (-not $ok) { Write-Host ' The download did not complete.' -ForegroundColor Red; Pause-Console; return }

        Write-Host ' Checking the SHA-256 fingerprint...' -ForegroundColor Cyan
        if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $sha) {
            Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
            Write-Host ' The downloaded file is damaged (fingerprint mismatch) - not installed.' -ForegroundColor Red
            Pause-Console; return
        }
        Write-Host ' Verified. Installing...' -ForegroundColor Green
        $rc = Invoke-WslInline @('--install', '--from-file', $file, '--name', $name, '--location', $loc, '--no-launch')
        Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
        if ($rc -eq 0) { Show-DownloadDone; return }
        Write-Host "`n The install failed (exit code $rc)." -ForegroundColor Red
    } catch {
        Write-Host " The resumable download did not work either: $_" -ForegroundColor Red
        Write-Host ' Check your internet connection and try again later.'
    }
    Pause-Console
}

function Show-DownloadDone {
    Write-Host "`n Finished. To set it up, pick it from the list, choose Accounts -> [A] and" -ForegroundColor Green
    Write-Host ' answer Y - that creates your Linux username and password. (Ubuntu/Debian also'
    Write-Host ' ask for one the first time you open a Terminal; Arch and some others do not -'
    Write-Host ' they start as root.)'
    Pause-Console
}

# ------------------------------------------------------------------------------
# .wslconfig (memory / CPU limits)
# ------------------------------------------------------------------------------
function Show-TuningMenu {
    Show-Header 'WSL resource limits (.wslconfig)'
    $path = Join-Path $HOME '.wslconfig'
    Write-Host " Settings file: $path" -ForegroundColor DarkGray
    Write-Host ''
    if (Test-Path -LiteralPath $path) {
        Write-Host ' Current contents:' -ForegroundColor Yellow
        Get-Content -LiteralPath $path | ForEach-Object { Write-Host "   $_" }
    } else {
        Write-Host ' No .wslconfig yet (WSL uses its defaults: up to 50% of your RAM).' -ForegroundColor DarkGray
    }
    Write-Host ''
    Write-Host '   [1] Light:    4 GB RAM, 2 CPU cores, 2 GB swap'
    Write-Host '   [2] Balanced: 8 GB RAM, 4 CPU cores, 4 GB swap'
    Write-Host '   [3] Heavy:    16 GB RAM, 6 CPU cores, 8 GB swap'
    Write-Host '   [4] Custom values'
    Write-Host "   [D] Reset memory / CPU / swap to WSL's defaults (other settings are kept)"
    Write-Host '   [B] Back'
    $opt = (Read-Line ' Enter your choice').ToUpper()

    if ($opt -eq '1') { $mem = '4GB'; $cpu = '2'; $swap = '2GB' }
    elseif ($opt -eq '2') { $mem = '8GB'; $cpu = '4'; $swap = '4GB' }
    elseif ($opt -eq '3') { $mem = '16GB'; $cpu = '6'; $swap = '8GB' }
    elseif ($opt -eq '4') {
        $mem = Read-Line ' Memory limit (e.g. 6GB)'
        $cpu = Read-Line ' Processors (e.g. 4)'
        $swap = Read-Line ' Swap size (e.g. 2GB, or 0)'
        if ($mem -notmatch '^\d+(GB|MB)$' -or $cpu -notmatch '^\d+$' -or $swap -notmatch '^\d+(GB|MB)?$') {
            Write-Host ' Those values do not look right (use e.g. 6GB, 4, 2GB) - nothing changed.' -ForegroundColor Red
            Pause-Console; return
        }
    }
    elseif ($opt -eq 'D') { $mem = $null; $cpu = $null; $swap = $null }
    else { return }

    # Only these three keys change; any other setting in the file stays.
    # A copy of the old file is still kept, just in case.
    $old = @()
    if (Test-Path -LiteralPath $path) {
        $old = [System.IO.File]::ReadAllLines($path)
        Copy-Item -LiteralPath $path -Destination "$path.bak" -Force
        Write-Host ' (your previous file was saved as .wslconfig.bak)' -ForegroundColor DarkGray
    }
    $new = Update-WslConfigLines $old ([ordered]@{ memory = $mem; processors = $cpu; swap = $swap })
    if (-not ($new | Where-Object { $_.Trim() -ne '' -and $_.Trim() -ine '[wsl2]' })) {
        # Nothing left but an empty [wsl2] section: WSL's defaults need no file.
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    } else {
        [System.IO.File]::WriteAllLines($path, [string[]]$new, (New-Object System.Text.UTF8Encoding($false)))
    }
    if ($opt -eq 'D') { Write-Host "`n Memory / CPU / swap limits removed - WSL uses its defaults again." -ForegroundColor Green }
    else { Write-Host "`n .wslconfig updated." -ForegroundColor Green }
    Write-Host ' Use [S] Shut down ALL WSL for it to take effect.' -ForegroundColor Green
    Pause-Console
}

# Sets the given keys in the [wsl2] section of .wslconfig lines (a $null value
# removes that key) and leaves every other line exactly as it was.
function Update-WslConfigLines([string[]]$lines, $values) {
    $out = New-Object System.Collections.Generic.List[string]
    $done = @{}
    $addMissing = {
        # Above any blank lines that close the section, not after them.
        $at = $out.Count
        while ($at -gt 0 -and $out[$at - 1].Trim() -eq '') { $at-- }
        foreach ($k in $values.Keys) {
            if ($null -ne $values[$k] -and -not $done[$k]) { $out.Insert($at, "$k=$($values[$k])"); $at++; $done[$k] = $true }
        }
    }
    $inWsl2 = $false; $seenWsl2 = $false
    foreach ($line in $lines) {
        if ($line -match '^\s*\[(.+?)\]\s*$') {
            if ($inWsl2) { & $addMissing }
            $inWsl2 = ($Matches[1].Trim() -ieq 'wsl2')
            if ($inWsl2) { $seenWsl2 = $true }
        } elseif ($inWsl2 -and $line -match '^\s*([A-Za-z0-9_.]+)\s*=') {
            $name = $Matches[1]
            $key = @($values.Keys | Where-Object { $_ -ieq $name }) | Select-Object -First 1
            if ($key) {
                if ($null -ne $values[$key] -and -not $done[$key]) { $out.Add("$key=$($values[$key])"); $done[$key] = $true }
                continue
            }
        }
        $out.Add($line)
    }
    if ($inWsl2) { & $addMissing }
    elseif (-not $seenWsl2 -and @($values.Values | Where-Object { $null -ne $_ }).Count -gt 0) {
        if ($out.Count -gt 0) { $out.Add('') }
        $out.Add('[wsl2]')
        & $addMissing
    }
    return ,$out.ToArray()
}

# ------------------------------------------------------------------------------
# Where data is saved
# ------------------------------------------------------------------------------
function Show-DataFoldersMenu {
    while ($true) {
        Show-Header 'Where your data is saved'
        Write-Host " Settings + saved logins: $CONFIG_FOLDER" -ForegroundColor DarkGray
        Write-Host '   (always next to the panel - the encrypted passwords belong to this Windows login)' -ForegroundColor DarkGray
        Write-Host ''
        Write-Host "   [1] Linux disks (new distros): $($Global:Config.WslBase)"
        Write-Host "   [2] Backups:                   $($Global:Config.BackupBase)"
        Write-Host '   [D] Put both back to the default folders'
        Write-Host '   [B] Back'
        Write-Host ''
        Write-Host ' A change only applies to NEW distros and NEW backups; existing ones stay where they are.' -ForegroundColor DarkGray
        $opt = (Read-Line ' Enter your choice').ToUpper()
        if ($opt -eq 'B' -or $opt -eq '') { return }
        elseif ($opt -eq 'D') {
            $Global:Config.WslBase = Join-Path $DATA_FOLDER 'linux'
            $Global:Config.BackupBase = Join-Path $DATA_FOLDER 'backups'
            Save-Config
            Write-Host ' Back to the default folders.' -ForegroundColor Green
            Pause-Console
        }
        elseif ($opt -eq '1' -or $opt -eq '2') {
            $what = $(if ($opt -eq '1') { 'Where should NEW Linux disks be saved?' } else { 'Where should NEW backups be saved?' })
            $cur = $(if ($opt -eq '1') { $Global:Config.WslBase } else { $Global:Config.BackupBase })
            $new = Read-Folder $what $cur
            if ($null -eq $new -or $new -eq $cur) { continue }
            try {
                if (-not (Test-Path -LiteralPath $new)) { New-Item -ItemType Directory -Path $new -Force | Out-Null }
            } catch {
                Write-Host " Could not create that folder: $($_.Exception.Message)" -ForegroundColor Red
                Pause-Console; continue
            }
            if ($opt -eq '1') { $Global:Config.WslBase = $new } else { $Global:Config.BackupBase = $new }
            Save-Config
            Write-Host ' Saved.' -ForegroundColor Green
            Pause-Console
        }
    }
}

# ------------------------------------------------------------------------------
# Main menu
# ------------------------------------------------------------------------------
function Show-MainMenu {
    while ($true) {
        $all = @(Get-WslDistros)
        $distros = @($all | Where-Object { -not $_.IsSystem })
        $hidden = @($all | Where-Object { $_.IsSystem })
        Show-Header 'Dashboard'
        Write-Host ' Installed distros:' -ForegroundColor Yellow
        Write-Host '----------------------------------------------------------------' -ForegroundColor DarkGray
        if ($distros.Count -eq 0) {
            Write-Host ' (none yet - use [N] below to download your first distro)' -ForegroundColor DarkGray
        }
        for ($i = 0; $i -lt $distros.Count; $i++) {
            $d = $distros[$i]
            $vhd = Get-DistroVhdInfo $d.Name
            $color = $(if ($d.State -eq 'Running') { 'Green' } else { 'DarkGray' })
            Write-Host ("  [{0}] {1} {2} " -f ($i + 1), $(if ($d.IsDefault) { '*' } else { ' ' }), $d.Name.PadRight(18)) -NoNewline
            Write-Host ("[{0}]" -f $d.State.ToUpper()).PadRight(12) -ForegroundColor $color -NoNewline
            Write-Host ("WSL{0}   {1} GB" -f $d.Version, $vhd.SizeGB) -ForegroundColor DarkGray
        }
        if ($hidden.Count -gt 0) {
            Write-Host " (hidden: $(($hidden | ForEach-Object { $_.Name }) -join ', ') - they belong to Docker/Rancher Desktop)" -ForegroundColor DarkGray
        }
        Write-Host '----------------------------------------------------------------' -ForegroundColor DarkGray
        Write-Host ''
        Write-Host " Press ENTER to quick-open your default distro's desktop, or pick a number to manage it."
        Write-Host ''
        Write-Host '   [C] Close a running distro   - stops one distro, frees its RAM'
        Write-Host '   [S] Shut down ALL WSL        - stops everything, frees the WSL VM'
        Write-Host '   [N] Download a NEW distro    - "wsl --install", with a resumable fallback'
        Write-Host '   [E] Back up a distro         - "wsl --export" to one .tar / .vhdx file'
        Write-Host '   [R] Restore a backup         - "wsl --import" brings a backup back'
        Write-Host '   [K] Compact a disk           - give unused ext4.vhdx space back to Windows'
        Write-Host '   [T] Memory / CPU limits      - edit .wslconfig'
        Write-Host '   [D] Data folders             - choose where Linux disks and backups are saved'
        Write-Host '   [U] Update / repair WSL      - runs "wsl --update" (admin)'
        Write-Host '   [Q] Quit                     - close the panel (distros keep running)'
        Write-Host ''
        $choice = (Read-Line ' Enter your choice').ToUpper()

        if ($choice -eq 'Q') { return }
        elseif ($choice -eq '') {
            if ($distros.Count -eq 0) { Write-Host "`n No distros installed yet - use [N]." -ForegroundColor Yellow; Pause-Console; continue }
            $target = $distros | Where-Object { $_.IsDefault } | Select-Object -First 1
            if (-not $target) { $target = $distros[0] }
            $accts = @(Get-SavedAccounts $target.Name)
            Start-DistroDesktop $target.Name $(if ($accts.Count -gt 0) { $accts[0] } else { $null })
        }
        elseif ($choice -eq 'C') {
            $running = @(Get-RunningDistros)
            if ($running.Count -eq 0) { Write-Host "`n No distros are running - nothing to close." -ForegroundColor Yellow; Pause-Console; continue }
            Write-Host "`n Running distros:" -ForegroundColor Yellow
            for ($i = 0; $i -lt $running.Count; $i++) { Write-Host "   [$($i + 1)] $($running[$i])" }
            Write-Host '   [A] Close ALL running distros'
            Write-Host '   [B] Back'
            $rc = (Read-Line ' Which to close').ToUpper()
            if ($rc -eq 'A') {
                Stop-KexAll
                Invoke-WslQuiet @('--shutdown') | Out-Null
                Write-Host ' Done - everything is stopped.' -ForegroundColor Green
                Pause-Console
            } elseif (($ri = Get-ListIndex $rc $running.Count) -ge 0) {
                $t = $running[$ri]
                Write-Host " Shutting down $t ..." -ForegroundColor Yellow
                Stop-Distro $t
                Free-WslVm
                Write-Host " Done - $t is stopped." -ForegroundColor Green
                Pause-Console
            }
        }
        elseif ($choice -eq 'S') {
            if (-not (Read-YesNo 'This stops EVERY running distro and frees the WSL VM. Proceed?' $false)) { continue }
            Write-Host ' Running wsl --shutdown ...' -ForegroundColor Yellow
            Stop-KexAll
            Invoke-WslQuiet @('--shutdown') | Out-Null
            Start-Sleep -Seconds 4
            $vm = @(Get-Process -Name VmmemWSL -ErrorAction SilentlyContinue).Count
            if ($vm -eq 0) { Write-Host ' Done - the WSL VM (VmmemWSL) is closed and its memory is freed.' -ForegroundColor Green }
            else { Write-Host ' WSL is shutting down; VmmemWSL is still releasing - it clears within a minute.' -ForegroundColor Yellow }
            Write-Host ' (A separate "Vmmem" in Task Manager is NOT Linux - wsl --shutdown does not affect it.)' -ForegroundColor DarkGray
            Pause-Console
        }
        elseif ($choice -eq 'N') { Download-DistroMenu }
        elseif ($choice -eq 'E') { Export-DistroMenu }
        elseif ($choice -eq 'R') { Import-DistroMenu }
        elseif ($choice -eq 'T') { Show-TuningMenu }
        elseif ($choice -eq 'D') { Show-DataFoldersMenu }
        elseif ($choice -eq 'K') {
            if ($distros.Count -eq 0) { continue }
            Write-Host "`n Compact which distro?" -ForegroundColor Yellow
            for ($i = 0; $i -lt $distros.Count; $i++) { Write-Host "   [$($i + 1)] $($distros[$i].Name)" }
            $kc = Read-Line ' Enter your choice'
            $ki = Get-ListIndex $kc $distros.Count
            if ($ki -ge 0) { Compact-DistroDisk $distros[$ki].Name }
        }
        elseif ($choice -eq 'U') {
            Show-Header 'Update / repair WSL'
            Write-Host " This updates the WSL platform (fixes many `"won't start`" / kernel problems)."
            Write-Host ' It needs administrator rights - click YES on the Windows prompt.'
            Write-Host ' Your distros and their files are NOT touched.'
            if (-not (Read-YesNo 'Update WSL now?' $false)) { continue }
            try {
                Start-Process -FilePath 'cmd.exe' -Verb RunAs -Wait -ArgumentList (Join-WinArgs @('/c', 'wsl --update & echo. & pause'))
            } catch { Write-Host ' The administrator prompt was declined or failed.' -ForegroundColor Red }
            Pause-Console
        }
        elseif (($di = Get-ListIndex $choice $distros.Count) -ge 0) {
            Show-DistroMenu $distros[$di].Name
        }
        else {
            Write-Host "`n That was not a valid choice." -ForegroundColor Red
            Pause-Console
        }
    }
}

# ------------------------------------------------------------------------------
# Entry point. Any unexpected error is shown (never a silently vanishing window).
# ------------------------------------------------------------------------------
try {
    if (Confirm-WslReady) { Show-MainMenu }
} catch [System.IO.EndOfStreamException] {
    # Input was closed (e.g. piped input ended) - just leave.
} catch {
    Write-Host ''
    Write-Host ' The WSL Control Panel hit an unexpected error:' -ForegroundColor Red
    Write-Host "   $($_.Exception.Message)" -ForegroundColor Red
    if ($_.ScriptStackTrace) { Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray }
    Pause-Console 'Press any key to close...'
    exit 1
}
