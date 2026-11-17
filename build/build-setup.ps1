# ==============================================================================
# WSL Control Panel - builds the release files (Windows only).
#
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File build\build-setup.ps1
#
# 1. Stages only what the app needs: "WSL Control Panel.exe" (compiled from
#    build\Launcher.cs) and app\.
# 2. Compiles build\setup.iss with Inno Setup 6 (installed with Chocolatey
#    when missing, as on GitHub's Windows machines).
# 3. Zips the same staged folder as the portable copy: unzip anywhere and run.
#    It has no unins000.exe, which is how the app knows it is portable.
# 4. Writes SHA256SUMS.txt for both, which the app's updater checks a
#    downloaded Setup against (and people can check their download with).
# The version comes from $PANEL_VERSION in app\windows\WSL-Control-Panel.ps1.
# Output in release\ (not saved in git): WSL-Control-Panel-Setup.exe, WSL-Control-Panel-Portable.zip
# and WSL-Control-Panel-SHA256SUMS.txt. Used by the Checks and Release
# workflows on GitHub.
#
# Keep this file plain ASCII (Windows PowerShell 5.1 reads it as ANSI).
# ==============================================================================
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$build = Join-Path $root 'release'
$stage = Join-Path $build 'stage'

$text = Get-Content -LiteralPath (Join-Path $root 'app\windows\WSL-Control-Panel.ps1') -Raw
if ($text -notmatch "PANEL_VERSION\s*=\s*'([^']+)'") { throw 'PANEL_VERSION not found.' }
$version = $Matches[1]
"Version $version"

# 1. Stage the app.
if (Test-Path -LiteralPath $build) { Remove-Item -LiteralPath $build -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stage | Out-Null
Copy-Item -LiteralPath (Join-Path $root 'app') -Destination (Join-Path $stage 'app') -Recurse
$out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File (Join-Path $root 'build\build-launcher.ps1') -Source $root -Dest $stage
if ($LASTEXITCODE -ne 0) { throw "Building the exe failed: $($out -join "`n")" }
. (Join-Path $root 'app\windows\AppIcon.ps1')
$ico = Join-Path $build 'app.ico'
Save-AppIco $ico '#0078D4'

# 2. Compile the Setup.
$iscc = @("${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "$env:ProgramFiles\Inno Setup 6\ISCC.exe") |
    Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $iscc) {
    'Installing Inno Setup ...'
    & choco install innosetup -y --no-progress | Out-Null
    $iscc = @("${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "$env:ProgramFiles\Inno Setup 6\ISCC.exe") |
        Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $iscc) { throw 'Inno Setup 6 could not be installed.' }
}
& $iscc /Q "/DAppVersion=$version" "/DStage=$stage" "/DIcon=$ico" "/DOutDir=$build" (Join-Path $PSScriptRoot 'setup.iss')
if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed (exit code $LASTEXITCODE)." }
$setup = Join-Path $build 'WSL-Control-Panel-Setup.exe'
if (-not (Test-Path -LiteralPath $setup)) { throw 'The Setup was not created.' }

# 3. The portable copy: the staged folder as it is.
$zip = Join-Path $build 'WSL-Control-Panel-Portable.zip'
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($stage, $zip, [System.IO.Compression.CompressionLevel]::Optimal, $false)

# 4. Checksums, in the format of sha256sum (lowercase hash, two spaces, name).
$sums = Join-Path $build 'WSL-Control-Panel-SHA256SUMS.txt'
$lines = foreach ($f in $setup, $zip) { '{0}  {1}' -f (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash.ToLowerInvariant(), (Split-Path -Leaf $f) }
[System.IO.File]::WriteAllLines($sums, [string[]]$lines, (New-Object System.Text.UTF8Encoding($false)))

foreach ($f in $setup, $zip, $sums) { "Built $f ($([math]::Round((Get-Item -LiteralPath $f).Length / 1KB)) KB)" }
