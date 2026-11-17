# ==============================================================================
# WSL Control Panel - builds "WSL Control Panel.exe" from Launcher.cs.
#
# Run by install.ps1 (always with Windows PowerShell 5.1, -STA):
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File build\build-launcher.ps1 -Source <download> -Dest <panel folder>
# -Source holds this source (build\Launcher.cs, app\windows\AppIcon.ps1);
# only the finished exe is written to -Dest.
# Uses the C# compiler of .NET Framework 4, which is part of Windows 10 and 11,
# and references the PowerShell that comes with Windows - nothing to install.
# The app icon (in your Windows accent colour) is built into the exe.
#
# Keep this file plain ASCII (Windows PowerShell 5.1 reads it as ANSI).
# ==============================================================================
param([Parameter(Mandatory = $true)][string]$Dest, [string]$Source = '')

$ErrorActionPreference = 'Stop'
if (-not $Source) { $Source = $Dest }
$ico = Join-Path $env:TEMP ('wsl-control-panel-' + [guid]::NewGuid().ToString('N') + '.ico')
try {
    . (Join-Path $Source 'app\windows\AppIcon.ps1')
    Save-AppIco $ico (Get-WindowsAccent)

    $csc = Join-Path ([Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()) 'csc.exe'
    if (-not (Test-Path -LiteralPath $csc)) { throw "The C# compiler of .NET Framework 4 was not found ($csc)." }
    $exe = Join-Path $Dest 'WSL Control Panel.exe'
    $src = Join-Path $Source 'build\Launcher.cs'
    $sma = [psobject].Assembly.Location

    # The compiler may write to stderr; that must not stop this script.
    $ErrorActionPreference = 'Continue'
    $out = & $csc /nologo /target:winexe /platform:anycpu /optimize+ "/out:$exe" "/win32icon:$ico" "/reference:$sma" $src 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($code -ne 0 -or -not (Test-Path -LiteralPath $exe)) {
        Write-Output ("The compiler said:`n" + (($out | ForEach-Object { "$_" }) -join "`n"))
        exit 1
    }
    Write-Output $exe
    exit 0
} catch {
    Write-Output $_.Exception.Message
    exit 1
} finally {
    Remove-Item -LiteralPath $ico -Force -ErrorAction SilentlyContinue
}
