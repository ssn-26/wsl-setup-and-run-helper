# ==============================================================================
# WSL Control Panel - engine
# Everything the panel does, with no window and no console prompts: the window
# (WSL-Control-Panel.ps1) dot-sources this file, and so does every background
# task it runs. Functions return results; progress goes to Write-TaskLog.
#
# Keep this file plain ASCII: Windows PowerShell 5.1 reads a BOM-less script as
# ANSI, so any fancy character could break parsing.
# ==============================================================================

# WSL_UTF8=1 makes wsl.exe print UTF-8 instead of UTF-16 (children inherit it).
$env:WSL_UTF8 = '1'

# Folder layout (this file lives in <root>\powershell):
#   <root>\WSL-Control-Panel.bat   start file
#   <root>\bash\                   the Linux-side scripts
#   <root>\powershell\             this engine + the window (WSL-Control-Panel.ps1, ui\)
#   <root>\data\config\            config.json + saved accounts (encrypted passwords)
#   <root>\data\backups\           backups                     (location can be changed)
#   <root>\data\linux\             one folder per distro disk  (location can be changed)
#   <root>\data\logs\              output of desktop installs
$SCRIPT_DIR = $PSScriptRoot
$ROOT_DIR = Split-Path -Parent $SCRIPT_DIR

$SCRIPTS_FOLDER  = Join-Path $ROOT_DIR 'bash'
$DATA_FOLDER     = Join-Path $ROOT_DIR 'data'
$CONFIG_FOLDER   = Join-Path $DATA_FOLDER 'config'
$ACCOUNTS_FOLDER = Join-Path $CONFIG_FOLDER 'accounts'
$LOGS_FOLDER     = Join-Path $DATA_FOLDER 'logs'
$CONFIG_FILE     = Join-Path $CONFIG_FOLDER 'config.json'

# ==============================================================================
# Building blocks (moved unchanged from the text panel, v1.3.1)
# ==============================================================================

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
        throw "Missing helper file: $path`n  Keep the 'bash' folder next to the 'powershell' folder."
    }
    return ((Get-Content -LiteralPath $path -Raw) -replace "`r`n", "`n")
}

# A script that writes desktop session files, with a write_session function
# in front of it that prints bash/xsession (the one copy of that file).
function Get-ScriptWithSession([string]$name) {
    $session = (Get-ScriptText 'xsession').TrimEnd("`n")
    return "write_session() {`ncat <<'XSESSION_EOF'`n$session`nXSESSION_EOF`n}`n" + (Get-ScriptText $name)
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
    Write-TaskLog " Stopping Win-KeX on $distro ..."
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
        Write-TaskLog ' No distros left running - freeing the WSL VM memory...'
        Invoke-WslQuiet @('--shutdown') | Out-Null
    }
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
    Write-TaskLog "Creating user '$user' inside $distro - please wait, this can take a minute or two..."
    $res = Invoke-WslScript $distro 'root' (Get-ScriptWithSession 'create-user.sh') @($user)
    foreach ($l in $res.Output) { Write-TaskLog "   $l" }
    if ($res.ExitCode -ne 0) {
        Write-TaskLog " The user could not be created (exit code $($res.ExitCode))."
        return $false
    }
    Write-TaskLog '   - setting the password...'
    if (-not (Set-LinuxPassword $distro $user $password)) {
        Write-TaskLog ' Could not set the user/password in the distro.'
        return $false
    }
    Write-TaskLog ' Done - the Linux account is ready.'
    return $true
}

# True when the distro logs in as root by default (fresh download, no user yet).
function Test-RootDefault([string]$distro) {
    $uid = Invoke-WslQuiet @('-d', $distro, '-e', 'id', '-u')
    return ($uid.Output.Count -gt 0 -and $uid.Output[0] -eq '0')
}

# Makes <user> the distro's default login, so a Terminal opens as them too.
function Set-DefaultUser([string]$distro, [string]$user) {
    if ((Invoke-WslQuiet @('--manage', $distro, '--set-default-user', $user)).ExitCode -eq 0) { return }
    # Older WSL has no --manage; the same setting lives in /etc/wsl.conf
    # (used from the next start). $user is a checked Linux name.
    $script = "U=$user`n" + @'
touch /etc/wsl.conf
if grep -q '^\[user\]' /etc/wsl.conf; then
    sed -i '/^\[user\]/,/^\[/{/^default[[:space:]]*=/d}' /etc/wsl.conf
    sed -i "/^\[user\]/a default=$U" /etc/wsl.conf
else
    printf '\n[user]\ndefault=%s\n' "$U" >> /etc/wsl.conf
fi
'@
    Invoke-WslScript $distro 'root' $script | Out-Null
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

function Test-XrdpListening([string]$distro, [int]$port) {
    # "-p" shows the owning program, and only for THIS distro's own processes,
    # so a listener belonging to another distro does not count as ours.
    $cmd = "ss -lntp 2>/dev/null | grep ':$port ' | grep -q xrdp"
    return ((Invoke-WslQuiet @('-d', $distro, '-u', 'root', '-e', 'sh', '-c', $cmd)).ExitCode -eq 0)
}

# Starts the distro quietly. Returns $null when it is up, or WSL's own error
# text when it cannot start.
function Get-DistroStartError([string]$distro) {
    $res = Invoke-WslQuiet @('-d', $distro, '-u', 'root', '-e', 'true')
    if ($res.ExitCode -eq 0) { return $null }
    $msg = (@($res.Output) + @(([string]$res.StdError) -split "`r?`n") | Where-Object { $_ -and $_.Trim() }) -join ' '
    if (-not $msg) { $msg = "wsl.exe stopped with exit code $($res.ExitCode)." }
    return $msg
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


# ==============================================================================
# Step functions for the window. Each one does its job WITHOUT asking anything
# and returns a result; the window decides what to ask next. They may run in a
# background task, so progress goes to Write-TaskLog, never to the console.
# ==============================================================================

# Progress lines for the window. A background task sets $global:TaskSync (a
# synchronized queue the window reads); anywhere else the lines are dropped.
function Write-TaskLog([string]$line) {
    if ($global:TaskSync) { $global:TaskSync.Lines.Enqueue($line) }
}

# Runs wsl.exe hidden and sends its output to the task log line by line, so a
# long install shows live progress. stdin is the given file, or closed at once.
# Returns the exit code - WSL's own errors are NEGATIVE, so compare with 0.
function Invoke-WslStreamed([string[]]$ArgumentList, [string]$StdinFile = $null) {
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
    if ($StdinFile) {
        $bytes = [System.IO.File]::ReadAllBytes($StdinFile)
        $proc.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
        $proc.StandardInput.BaseStream.Flush()
    }
    $proc.StandardInput.Close()
    # ReadLine also splits on the bare CR that progress bars use. Old wsl.exe
    # prints UTF-16; dropping its zero bytes leaves readable text.
    $reader = New-Object System.IO.StreamReader($proc.StandardOutput.BaseStream, [System.Text.Encoding]::UTF8)
    $last = $null
    while ($null -ne ($line = $reader.ReadLine())) {
        $t = $line.Replace([string][char]0, '').TrimEnd()
        if ($t.Trim() -and $t -ne $last) { Write-TaskLog $t; $last = $t }
    }
    $proc.WaitForExit()
    foreach ($l in (([string]$errTask.Result) -split "`r?`n")) { if ($l.Trim()) { Write-TaskLog $l.TrimEnd() } }
    return $proc.ExitCode
}

# Marks the panel's own files as safe, so Windows' "are you sure you want to
# run this?" warning for files from a downloaded ZIP shows only the first time.
# data\ is skipped: it holds the large Linux disks and nothing that runs.
function Unblock-PanelFiles {
    foreach ($p in @((Join-Path $ROOT_DIR 'WSL-Control-Panel.bat'), $SCRIPT_DIR, $SCRIPTS_FOLDER)) {
        try {
            if (Test-Path -LiteralPath $p -PathType Leaf) { Unblock-File -LiteralPath $p -ErrorAction SilentlyContinue }
            elseif (Test-Path -LiteralPath $p) { Get-ChildItem -LiteralPath $p -Recurse -File -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue }
        } catch { }
    }
}

# ------------------------------------------------------------------------------
# WSL itself
# ------------------------------------------------------------------------------
# 'Ready' or 'NotInstalled'. The real WSL always installs to "C:\Program
# Files\WSL"; wsl.exe is never run before that exists, because on a PC where
# WSL was never set up Windows' built-in wsl.exe waits at a hidden 60-second
# "Press any key to install WSL" prompt.
function Get-WslState {
    if ((Test-WslFiles) -and ((Invoke-WslQuiet @('--version')).ExitCode -eq 0)) { return 'Ready' }
    return 'NotInstalled'
}

# First-time setup in an administrator window. Returns 'READY', 'RESTART'
# (Windows needs a restart to finish) or 'MISSING' (declined or failed).
function Install-WslPlatform {
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
    Write-TaskLog 'Asking for administrator rights - click YES on the Windows prompt...'
    if (-not (Invoke-ElevatedScript $setup)) { Write-TaskLog 'The administrator prompt was declined or failed.' }
    Write-TaskLog 'Checking whether WSL is ready...'
    $state = 'READY'
    if (-not (Test-WslFiles)) { $state = 'MISSING' }
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { $state = 'RESTART' }
    if ($state -eq 'READY' -and (Invoke-WslQuiet @('--version')).ExitCode -ne 0) { $state = 'RESTART' }
    return $state
}

# Runs "wsl --update" in an administrator window and waits. $false = declined.
function Update-WslPlatform {
    try {
        Start-Process -FilePath 'cmd.exe' -Verb RunAs -Wait -ArgumentList (Join-WinArgs @('/c', 'wsl --update & echo. & pause'))
        return $true
    } catch { return $false }
}

# Stops every distro and the WSL VM. Returns $true when the VM's memory is
# already free (VmmemWSL gone), $false when it is still being released.
function Stop-AllWsl {
    Write-TaskLog 'Running wsl --shutdown ...'
    Stop-KexAll
    Invoke-WslQuiet @('--shutdown') | Out-Null
    Start-Sleep -Seconds 4
    return (@(Get-Process -Name VmmemWSL -ErrorAction SilentlyContinue).Count -eq 0)
}

# Stops one distro, then frees the WSL VM if nothing else is running.
function Stop-OneDistro([string]$distro) {
    Write-TaskLog "Shutting down $distro ..."
    Stop-Distro $distro
    Free-WslVm
}

# ------------------------------------------------------------------------------
# Opening a distro
# ------------------------------------------------------------------------------
# Linux user names the panel accepts (what useradd takes on every distro).
function Test-LinuxUserName([string]$name) { return ($name -cmatch '^[a-z_][a-z0-9_-]{0,31}$') }

# The Windows user name as a Linux name, when it makes a valid one ('' if not).
function Get-SuggestedUserName {
    $s = ($env:USERNAME -replace '[^A-Za-z0-9_-]', '').ToLower()
    if (Test-LinuxUserName $s) { return $s }
    return ''
}

# Starts the distro and checks the chosen saved login. Used before a Terminal
# opens. Status: Ready | StartFailed (Error, Locked) | UserMissing (Account).
function Test-DistroReady([string]$distro, [string]$account = '') {
    Write-TaskLog "Waking $distro ..."
    $err = Get-DistroStartError $distro
    if ($err) { return @{ Status = 'StartFailed'; Error = $err; Locked = ($err -match 'SHARING_VIOLATION|being used by another process') } }
    if ($account -and -not (Test-LinuxUserExists $distro $account)) { return @{ Status = 'UserMissing'; Account = $account } }
    return @{ Status = 'Ready' }
}

# The usual fixes when a distro cannot start: 'Shutdown' (a stuck WSL) or
# 'Detach' (Windows mounted its ext4.vhdx; needs admin). $false = declined.
function Repair-DistroStart([string]$distro, [string]$how) {
    if ($how -eq 'Detach') {
        $p = (Get-DistroVhdInfo $distro).VhdxPath -replace "'", "''"
        Write-TaskLog 'Detaching the disk from Windows (a security prompt appears - click YES)...'
        return (Invoke-ElevatedScript "try { Dismount-DiskImage -ImagePath '$p' -ErrorAction Stop | Out-Null } catch { }")
    }
    Write-TaskLog 'Shutting WSL down ...'
    Stop-KexAll
    Invoke-WslQuiet @('--shutdown') | Out-Null
    Start-Sleep -Seconds 3
    return $true
}

# One attempt at opening a distro's desktop with an optional saved login.
# The Status tells the window what to do next:
#   StartFailed     WSL could not start it (Error, Locked)
#   UserMissing     the saved login's Linux user is gone (Account)
#   NeedsFirstUser  nothing saved and the distro only has root
#   KexNeedsUser    the Kali desktop cannot run as root and no user is chosen
#   PortConflict    another running distro's xrdp holds the port (Conflict, Port)
#   NeedsInstall    no desktop server the panel can open (Port, IsKali)
#   NotReachable    a desktop was just installed but xrdp still does not answer
#   OpenedRdp / OpenedKex   done (WithLogin = a saved login was used)
function Open-DistroDesktop([string]$distro, [string]$account = '', [switch]$AfterInstall, [switch]$SkipFirstUser) {
    $ready = Test-DistroReady $distro $account
    if ($ready.Status -ne 'Ready') { return $ready }
    $acct = $null
    if ($account) { $acct = Get-SavedAccounts $distro | Where-Object { $_.Username -eq $account } | Select-Object -First 1 }
    # Nothing saved and the distro only has root: the window creates the user
    # first, then calls this again with it.
    if (-not $acct -and -not $SkipFirstUser -and @(Get-SavedAccounts $distro).Count -eq 0 -and (Test-RootDefault $distro)) {
        return @{ Status = 'NeedsFirstUser' }
    }

    Write-TaskLog "Detecting the desktop type of $distro ..."
    # kex alone is not enough: on a minimal Kali, kali-win-kex installs without
    # the XFCE it runs, and the VNC server starts, finds no desktop and exits.
    $hasKex  = ((Invoke-WslQuiet @('-d', $distro, '--', 'bash', '-lc', 'command -v kex >/dev/null 2>&1')).ExitCode -eq 0)
    $hasXfce = $hasKex -and ((Invoke-WslQuiet @('-d', $distro, '--', 'bash', '-lc', 'command -v startxfce4 >/dev/null 2>&1')).ExitCode -eq 0)
    if ($hasKex -and $hasXfce) {
        # Win-KeX must run as a NON-root user.
        if (-not $acct -and (Test-RootDefault $distro)) { return @{ Status = 'KexNeedsUser' } }
        Start-KexWindow $distro $acct
        return @{ Status = 'OpenedKex'; WithLogin = [bool]$acct }
    }

    $port = Get-DistroPort $distro
    $isKali = Test-KaliDistro $distro
    if (-not $isKali) {
        # All WSL2 distros share ONE network: if another running distro's xrdp
        # already holds this port, Remote Desktop would open THAT desktop instead.
        foreach ($rd in (Get-RunningDistros)) {
            if ($rd -ne $distro -and -not (Test-SystemDistro $rd) -and (Test-XrdpListening $rd $port)) {
                return @{ Status = 'PortConflict'; Conflict = $rd; Port = $port }
            }
        }
        Write-TaskLog "Starting the desktop server (xrdp, port $port) ..."
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
            Open-RdpWindow $distro $acct $port
            return @{ Status = 'OpenedRdp'; Port = $port; WithLogin = [bool]$acct }
        }
    }
    if ($AfterInstall) { return @{ Status = 'NotReachable'; Port = $port } }
    return @{ Status = 'NeedsInstall'; Port = $port; IsKali = $isKali }
}

# Gives <distro> the next port that no running distro listens on, and saves it.
function Set-NextFreePort([string]$distro, [int]$port) {
    $busy = @{}
    foreach ($rd in (Get-RunningDistros)) {
        $res = Invoke-WslQuiet @('-d', $rd, '-u', 'root', '-e', 'sh', '-c', "ss -lnt 2>/dev/null | awk 'NR>1{n=split(`$4,a,`":`"); print a[n]}'")
        foreach ($l in $res.Output) { $busy[$l.Trim()] = $true }
    }
    $np = $port + 1
    while ($busy.ContainsKey([string]$np) -or $np -eq 3389) { $np++ }
    Set-DistroPort $distro $np
    return $np
}

# Opens Windows Remote Desktop on the distro's xrdp, logged in with the saved
# account when there is one. The .rdp file holds the encrypted login, so it is
# deleted once mstsc has read it.
function Open-RdpWindow([string]$distro, $account, [int]$port) {
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
    Write-TaskLog 'Opening Windows Remote Desktop (mstsc)...'
    Start-Process -FilePath 'mstsc.exe' -ArgumentList (Join-WinArgs @($rdp))
    Start-Sleep -Seconds 5
    Remove-Item -LiteralPath $rdp -Force -ErrorAction SilentlyContinue
}

# Starts the Kali desktop (Win-KeX) in its own console window.
function Start-KexWindow([string]$distro, $account) {
    $userArgs = @()
    if ($account -and $account.Username) { $userArgs = @('-u', $account.Username) }
    Write-TaskLog "Starting the Kali (Win-KeX) desktop for $distro ..."
    Start-KeepAlive $distro
    # cd ~ avoids the "started from a Windows dir" passwd-file failure; the visible
    # console gives the first-run password prompt a terminal; systemctl
    # set-environment stops XFCE helpers (e.g. notification daemon) falling back
    # to WSLg and popping an error window on Windows.
    $kexCmd = "cd ~ && unset WAYLAND_DISPLAY && { systemctl --user set-environment DISPLAY=:1 GDK_BACKEND=x11 XDG_SESSION_TYPE=x11 2>/dev/null; kex --win; }; echo; read -rp 'Desktop is in its own window. Press Enter to close this console. '"
    Start-Process -FilePath (Get-WslExe) -ArgumentList (Join-WinArgs (@('-d', $distro) + $userArgs + @('--', 'bash', '-lc', $kexCmd)))
}

# Installs the XFCE desktop (+ xrdp, or Kali's Win-KeX). The output is shown
# live AND saved to data\logs. Returns @{ Ok; ExitCode; Log }.
function Install-DistroDesktop([string]$distro, [int]$port, [bool]$isKali) {
    $log = '/var/log/wsl-panel-desktop-install.log'
    if ($isKali) {
        Write-TaskLog "Installing Kali's XFCE desktop + Win-KeX (about 1-2 GB - this can take a while)..."
        $cmd = '{ set -e; export DEBIAN_FRONTEND=noninteractive; apt-get update && apt-get install -y kali-desktop-xfce dbus-x11 kali-win-kex; } 2>&1 | tee ' + $log + '; exit ${PIPESTATUS[0]}'
        $rc = Invoke-WslStreamed @('-d', $distro, '-u', 'root', '--', 'bash', '-lc', $cmd)
    } else {
        Write-TaskLog "Installing an XFCE desktop + xrdp (port $port) on $distro ..."
        Write-TaskLog '(auto-detecting the package manager - this can take several minutes)'
        # The installer travels through stdin from a temp file, so no command
        # line has to carry it.
        $tmp = Join-Path $env:TEMP 'wsl-desktop-setup.b64'
        Set-Content -LiteralPath $tmp -Value (ConvertTo-Base64 (Get-ScriptWithSession 'install-desktop.sh')) -Force -Encoding Ascii
        $cmd = "tr -d '\r' | base64 -d > /tmp/wsl-desktop-setup.sh && { bash /tmp/wsl-desktop-setup.sh $port </dev/null 2>&1 | tee $log; rc=`${PIPESTATUS[0]}; rm -f /tmp/wsl-desktop-setup.sh; exit `$rc; }"
        $rc = Invoke-WslStreamed @('-d', $distro, '-u', 'root', '-e', 'bash', '-c', $cmd) $tmp
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
    $saved = Save-DistroLog $distro $log 'desktop-install'
    return @{ Ok = ($rc -eq 0); ExitCode = $rc; Log = $saved }
}

# Opens a Terminal window (Windows Terminal when installed), as the saved
# login when one is given.
function Open-DistroTerminal([string]$distro, [string]$account = '') {
    $a = @('-d', $distro)
    if ($account) { $a += @('-u', $account) }
    $wt = Get-Command wt.exe -ErrorAction SilentlyContinue
    if ($wt) { Start-Process -FilePath $wt.Source -ArgumentList (Join-WinArgs (@('wsl.exe') + $a)) }
    else     { Start-Process -FilePath (Get-WslExe) -ArgumentList (Join-WinArgs $a) }
}

# ------------------------------------------------------------------------------
# Accounts
# ------------------------------------------------------------------------------
# Saves a login (and with $createInLinux also makes the Linux user: sudo
# rights + desktop session + password). Returns $true on success.
function Add-PanelAccount([string]$distro, [string]$user, [string]$password, [bool]$createInLinux) {
    if ($createInLinux -and -not (New-LinuxUser $distro $user $password)) { return $false }
    Save-EncryptedAccount $distro $user $password
    return $true
}

# The first user of a fresh distro: created, saved, and made the default login
# so a Terminal opens as them too.
function New-FirstUser([string]$distro, [string]$user, [string]$password) {
    if (-not (Add-PanelAccount $distro $user $password $true)) { return $false }
    Set-DefaultUser $distro $user
    Write-TaskLog " '$user' is now the default login, so a Terminal opens as you too."
    return $true
}

# Changes the password in Linux and, only if that worked, in the panel.
function Set-AccountPassword([string]$distro, [string]$user, [string]$password) {
    Write-TaskLog "Setting the new password for '$user' ..."
    if (-not (Set-LinuxPassword $distro $user $password)) { return $false }
    Save-EncryptedAccount $distro $user $password
    return $true
}

# ------------------------------------------------------------------------------
# Distro settings
# ------------------------------------------------------------------------------
# Is systemd switched on in the distro's /etc/wsl.conf? (Starts the distro.)
function Get-SystemdEnabled([string]$distro) {
    $chk = Invoke-WslQuiet @('-d', $distro, '-u', 'root', '-e', 'sh', '-c', "grep -Eq '^[[:space:]]*systemd[[:space:]]*=[[:space:]]*true' /etc/wsl.conf 2>/dev/null && echo ENABLED || echo DISABLED")
    return ($chk.Output.Count -gt 0 -and $chk.Output[0] -eq 'ENABLED')
}

# Turns systemd on or off in /etc/wsl.conf and stops the distro so it applies
# at the next start. Returns $true on success.
function Set-SystemdEnabled([string]$distro, [bool]$enable) {
    if (-not $enable) {
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
    if ($res.ExitCode -ne 0) { return $false }
    Stop-Distro $distro
    return $true
}

# Hands unused ext4.vhdx space back to Windows: stops ALL of WSL, then either
# turns on sparse mode or compacts with diskpart (admin). Returns
# @{ Ok; Message; Kind } where Kind is 'Ok', 'Warn' or 'Error'.
function Invoke-CompactDisk([string]$distro, [bool]$sparse) {
    $vhd = Get-DistroVhdInfo $distro
    if (-not $vhd.Exists) { return @{ Ok = $false; Kind = 'Error'; Message = "Could not find ext4.vhdx for $distro." } }
    Write-TaskLog 'Shutting WSL down so the disk file is free...'
    Stop-KexAll
    Invoke-WslQuiet @('--shutdown') | Out-Null
    Start-Sleep -Seconds 3
    if ($sparse) {
        $res = Invoke-WslQuiet @('--manage', $distro, '--set-sparse', 'true')
        if ($res.ExitCode -eq 0) { return @{ Ok = $true; Kind = 'Ok'; Message = 'Sparse mode is on - WSL now reclaims free space by itself.' } }
        Write-TaskLog 'This WSL version refused sparse mode - compacting instead.'
    }
    # diskpart reads its commands from a pipe, so no script file is written.
    $vhdArg = $vhd.VhdxPath -replace "'", "''"
    $compact = "@('select vdisk file=`"$vhdArg`"', 'attach vdisk readonly', 'compact vdisk', 'detach vdisk', 'exit') | diskpart.exe"
    Write-TaskLog 'Compacting with diskpart (a Windows security prompt may appear - click YES)...'
    if (Test-IsAdmin) {
        @("select vdisk file=`"$($vhd.VhdxPath)`"", 'attach vdisk readonly', 'compact vdisk', 'detach vdisk', 'exit') | diskpart.exe | ForEach-Object { Write-TaskLog $_ }
    } elseif (-not (Invoke-ElevatedScript $compact)) {
        return @{ Ok = $false; Kind = 'Error'; Message = 'The administrator prompt was declined or failed - nothing was changed.' }
    }
    $after = Get-DistroVhdInfo $distro
    $saved = [math]::Round($vhd.SizeGB - $after.SizeGB, 2)
    if ($saved -gt 0) { return @{ Ok = $true; Kind = 'Ok'; Message = "Reclaimed $saved GB - the disk is now $($after.SizeGB) GB (was $($vhd.SizeGB) GB)." } }
    return @{ Ok = $true; Kind = 'Warn'; Message = "Nothing more could be reclaimed - the disk is $($after.SizeGB) GB." }
}

# "wsl --unregister": erases the distro. Its saved logins and port go too.
function Remove-WslDistro([string]$distro) {
    Write-TaskLog "Deleting $distro ..."
    Invoke-WslQuiet @('--unregister', $distro) | Out-Null
    Remove-Item -LiteralPath (Get-AccountFile $distro) -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Get-PortFile $distro) -Force -ErrorAction SilentlyContinue
}

# ------------------------------------------------------------------------------
# Download
# ------------------------------------------------------------------------------
# Microsoft's list of installable distros: @{ Rows = @(@{Name; Friendly}); Raw }.
# Rows are the lines with two or more spaces between columns, so the header
# text around the table (one space between words) is skipped in any language.
function Get-OnlineDistros {
    $res = Invoke-WslQuiet @('--list', '--online')
    $rows = @()
    foreach ($l in $res.Output) {
        if ($l -match '^\s*(\S+)\s{2,}(\S.*)$' -and $Matches[1] -cne 'NAME' -and (Test-DistroName $Matches[1])) {
            $rows += [pscustomobject]@{ Name = $Matches[1]; Friendly = $Matches[2].Trim() }
        }
    }
    return @{ Rows = $rows; Raw = $res.Output; ExitCode = $res.ExitCode }
}

# "wsl --install" into <base>\<name>. Returns @{ Ok; ExitCode; Location }.
function Install-WslDistro([string]$name, [string]$base) {
    $loc = Join-Path $base $name
    if (-not (Test-Path -LiteralPath $loc)) { New-Item -ItemType Directory -Path $loc -Force | Out-Null }
    Write-TaskLog "Installing $name into $loc - this downloads several hundred MB, please wait..."
    $rc = Invoke-WslStreamed @('--install', $name, '--location', $loc, '--no-launch')
    return @{ Ok = ($rc -eq 0); ExitCode = $rc; Location = $loc }
}

# The resumable fallback: fetches the same official image in pieces (it
# continues wherever the connection drops), checks its SHA-256 fingerprint,
# then installs it. Returns @{ Ok; Message }.
function Install-WslDistroResumable([string]$name, [string]$loc) {
    try {
        Write-TaskLog "Reading Microsoft's official distro list..."
        $json = Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/microsoft/WSL/master/distributions/DistributionInfo.json'
        # Each value is an array of entries, so unroll it before filtering.
        $entry = $json.ModernDistributions.PSObject.Properties.Value | ForEach-Object { $_ } | Where-Object { $_.Name -eq $name } | Select-Object -First 1
        if (-not $entry) { return @{ Ok = $false; Message = "'$name' has no downloadable image in Microsoft's list." } }
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

        Write-TaskLog "Downloading $url"
        Write-TaskLog '(resumable: if the server drops the connection it continues where it stopped)'
        $ok = $false
        for ($i = 1; $i -le 60; $i++) {
            # No 2>&1 here: in PowerShell 5.1 that turns curl's error text into
            # PowerShell errors, which would stop the download at the first drop.
            & curl.exe -L -C - -sS --max-time 300 -o $file $url | Out-Null
            if ($LASTEXITCODE -eq 0) { $ok = $true; break }
            Write-TaskLog "   connection dropped - resuming (attempt $i of 60)..."
            Start-Sleep -Seconds 2
        }
        if (-not $ok) { return @{ Ok = $false; Message = 'The download did not complete.' } }

        Write-TaskLog 'Checking the SHA-256 fingerprint...'
        if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $sha) {
            Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
            return @{ Ok = $false; Message = 'The downloaded file is damaged (fingerprint mismatch) - not installed.' }
        }
        Write-TaskLog 'Verified. Installing...'
        $rc = Invoke-WslStreamed @('--install', '--from-file', $file, '--name', $name, '--location', $loc, '--no-launch')
        Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
        if ($rc -eq 0) { return @{ Ok = $true; Message = "$name is installed." } }
        return @{ Ok = $false; Message = "The install failed (exit code $rc)." }
    } catch {
        return @{ Ok = $false; Message = "The resumable download did not work either: $($_.Exception.Message) Check your internet connection and try again later." }
    }
}

# ------------------------------------------------------------------------------
# Backup / restore
# ------------------------------------------------------------------------------
# "wsl --export" to <dir>\<name>_<date>.<tar|vhdx>; stops the distro first.
# Returns @{ Ok; File; GB; ExitCode }.
function Export-WslDistro([string]$name, [string]$dir, [string]$ext) {
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $file = Join-Path $dir ("{0}_{1}.{2}" -f $name, (Get-Date -Format 'yyyy-MM-dd_HHmm'), $ext)
    if ((Get-RunningDistros) -contains $name) { Write-TaskLog "Stopping $name ..."; Stop-Distro $name }
    Write-TaskLog "Exporting to $file - please wait (can take a few minutes)..."
    $a = @('--export', $name, $file)
    if ($ext -eq 'vhdx') { $a += '--vhd' }
    $rc = Invoke-WslStreamed $a
    $result = @{ Ok = $false; File = $file; GB = 0; ExitCode = $rc }
    if ($rc -eq 0 -and (Test-Path -LiteralPath $file)) {
        $result.Ok = $true
        $result.GB = [math]::Round((Get-Item -LiteralPath $file).Length / 1GB, 2)
    } else {
        Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
    }
    Free-WslVm
    return $result
}

# The newest 15 backups in the backups folder.
function Get-BackupFiles {
    $dir = $Global:Config.BackupBase
    if (-not (Test-Path -LiteralPath $dir)) { return @() }
    return @(Get-ChildItem -LiteralPath $dir -File | Where-Object { $_.Extension -in '.tar', '.vhdx' } |
        Sort-Object LastWriteTime -Descending | Select-Object -First 15)
}

# The distro name a backup file suggests: its name minus the _date_time part.
function Get-BackupDistroName([string]$file) {
    return ([System.IO.Path]::GetFileNameWithoutExtension($file) -replace '_\d{4}-\d{2}-\d{2}_\d{4}$', '')
}

# Why a restore cannot go ahead, or $null when it can.
function Get-RestoreProblem([string]$file, [string]$name, [string]$loc) {
    if (-not $file -or -not (Test-Path -LiteralPath $file -PathType Leaf)) { return 'The backup file was not found.' }
    if (-not (Test-DistroName $name)) { return 'A distro name can only use letters, digits, dot, - and _ (no spaces).' }
    if (Get-WslDistros | Where-Object { $_.Name -eq $name }) {
        return "A distro called '$name' is already installed. Restore under a different name (e.g. $name-restored) or delete the existing one first."
    }
    if (Test-Path -LiteralPath (Join-Path $loc 'ext4.vhdx')) { return "$loc already holds a distro disk (ext4.vhdx). Pick another folder." }
    return $null
}

# "wsl --import", then makes the first regular user inside the backup the
# default login (an import always starts as root). Returns @{ Ok; ExitCode; DefaultUser }.
function Import-WslDistro([string]$file, [string]$name, [string]$loc) {
    if (-not (Test-Path -LiteralPath $loc)) { New-Item -ItemType Directory -Path $loc -Force | Out-Null }
    Write-TaskLog "Restoring $name - this can take a few minutes..."
    $a = @('--import', $name, $loc, $file)
    if ($file.EndsWith('.vhdx', [System.StringComparison]::OrdinalIgnoreCase)) { $a += '--vhd' }
    $rc = Invoke-WslStreamed $a
    if ($rc -ne 0) { return @{ Ok = $false; ExitCode = $rc; DefaultUser = '' } }
    $user = ''
    $res = Invoke-WslQuiet @('-d', $name, '-u', 'root', '-e', 'sh', '-c', "getent passwd | awk -F: '`$3>=1000 && `$3<60000 {print `$1; exit}'")
    if ($res.Output.Count -gt 0 -and $res.Output[0] -match '^[a-z_][a-z0-9_-]*$') {
        $user = $res.Output[0]
        Invoke-WslQuiet @('--manage', $name, '--set-default-user', $user) | Out-Null
    }
    Invoke-WslQuiet @('--terminate', $name) | Out-Null
    Free-WslVm
    return @{ Ok = $true; ExitCode = 0; DefaultUser = $user }
}

# ------------------------------------------------------------------------------
# .wslconfig (memory / CPU limits) and data folders
# ------------------------------------------------------------------------------
function Get-WslConfigPath { return (Join-Path $HOME '.wslconfig') }

# Sets memory / processors / swap in .wslconfig ($null for all three = back to
# WSL's defaults). Only these keys change; a copy of the old file is kept.
function Set-WslLimits($mem, $cpu, $swap) {
    $path = Get-WslConfigPath
    $old = @()
    if (Test-Path -LiteralPath $path) {
        $old = [System.IO.File]::ReadAllLines($path)
        Copy-Item -LiteralPath $path -Destination "$path.bak" -Force
    }
    $new = Update-WslConfigLines $old ([ordered]@{ memory = $mem; processors = $cpu; swap = $swap })
    if (-not ($new | Where-Object { $_.Trim() -ne '' -and $_.Trim() -ine '[wsl2]' })) {
        # Nothing left but an empty [wsl2] section: WSL's defaults need no file.
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    } else {
        [System.IO.File]::WriteAllLines($path, [string[]]$new, (New-Object System.Text.UTF8Encoding($false)))
    }
}

# Custom limit values as the text panel accepted them (e.g. 6GB, 4, 2GB / 0).
function Test-LimitValues([string]$mem, [string]$cpu, [string]$swap) {
    return ($mem -match '^\d+(GB|MB)$' -and $cpu -match '^\d+$' -and $swap -match '^\d+(GB|MB)?$')
}

# Changes where NEW distros ('WslBase') or NEW backups ('BackupBase') go.
# Returns $null, or why the folder cannot be used.
function Set-DataFolder([string]$which, [string]$path) {
    if ($path -notmatch '^([A-Za-z]:\\|\\\\)') { return 'Please choose a FULL path that starts with a drive letter, e.g. E:\Linux' }
    if ($path.Length -gt 3) { $path = $path.TrimEnd('\') }
    try {
        if (-not (Test-Path -LiteralPath $path)) { New-Item -ItemType Directory -Path $path -Force | Out-Null }
    } catch { return "Could not create that folder: $($_.Exception.Message)" }
    $Global:Config.$which = $path
    Save-Config
    return $null
}

function Reset-DataFolders {
    $Global:Config.WslBase = Join-Path $DATA_FOLDER 'linux'
    $Global:Config.BackupBase = Join-Path $DATA_FOLDER 'backups'
    Save-Config
}

# ------------------------------------------------------------------------------
# Load the settings and create the data folders up front so the layout is
# visible (best effort - a folder on a drive that is not plugged in is skipped).
# ------------------------------------------------------------------------------
$Global:Config = Get-Config
foreach ($d in @($CONFIG_FOLDER, $ACCOUNTS_FOLDER, $Global:Config.WslBase, $Global:Config.BackupBase)) {
    try { if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null } } catch { }
}
