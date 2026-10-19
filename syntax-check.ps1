# Parses WSL-Control-Panel.ps1 and reports syntax errors WITHOUT running it.
# Run with Windows PowerShell 5.1 (what the launcher uses):
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File syntax-check.ps1
# PowerShell 7 accepts newer syntax (e.g. the ?. operator) that 5.1 rejects, so
# checking with pwsh can give a false "OK".
$errors = $null
$tokens = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot 'WSL-Control-Panel.ps1'),
    [ref]$tokens,
    [ref]$errors
)
$nonAscii = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'WSL-Control-Panel.ps1') -Raw).ToCharArray() | Where-Object { [int]$_ -gt 127 }
if ($nonAscii) { Write-Host "WARNING: the script contains non-ASCII characters (breaks PowerShell 5.1)." -ForegroundColor Yellow }
if ($errors.Count -eq 0) {
    Write-Host "SYNTAX OK (PowerShell $($PSVersionTable.PSVersion)) - no parse errors found." -ForegroundColor Green
    exit 0
}
Write-Host "PARSE ERRORS found:" -ForegroundColor Red
foreach ($err in $errors) {
    Write-Host ("  Line $($err.Extent.StartLineNumber): $($err.Message)") -ForegroundColor Yellow
}
exit 1
