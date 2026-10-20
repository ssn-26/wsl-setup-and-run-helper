# ==============================================================================
# WSL Control Panel - builds "WSL Control Panel.exe" from Launcher.cs.
#
# Run by install.ps1 (always with Windows PowerShell 5.1, -STA):
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File launcher\build.ps1 -Dest <panel folder>
# Uses the C# compiler of .NET Framework 4, which is part of Windows 10 and 11,
# and references the PowerShell that comes with Windows - nothing to install.
# Writes launcher\app.ico (the app icon in your Windows accent colour) first.
#
# Keep this file plain ASCII (Windows PowerShell 5.1 reads it as ANSI).
# ==============================================================================
param([Parameter(Mandatory = $true)][string]$Dest)

$ErrorActionPreference = 'Stop'
try {
    . (Join-Path $Dest 'powershell\AppIcon.ps1')
    $ico = Join-Path $Dest 'launcher\app.ico'
    Save-AppIco $ico (Get-WindowsAccent)

    $csc = Join-Path ([Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()) 'csc.exe'
    if (-not (Test-Path -LiteralPath $csc)) { throw "The C# compiler of .NET Framework 4 was not found ($csc)." }
    $exe = Join-Path $Dest 'WSL Control Panel.exe'
    $src = Join-Path $Dest 'launcher\Launcher.cs'
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
}
