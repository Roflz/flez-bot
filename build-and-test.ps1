# Quick build flez-bot.exe and test in place (no need to rebuild the full installer each time).
# Run from flez-bot repo root. After the first install, this copies the new exe to your install
# folder so you can run it immediately.
# Usage: .\build-and-test.ps1
#        .\build-and-test.ps1 -NoLaunch   # build and copy only, don't start the app

param([switch]$NoLaunch)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
Set-Location $root

Write-Host "Building flez-bot.exe..." -ForegroundColor Cyan
python -m PyInstaller flez-bot.spec
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$exe = Join-Path $root "dist\flez-bot.exe"
if (-not (Test-Path $exe)) {
    Write-Host "Build failed: dist\flez-bot.exe not found." -ForegroundColor Red
    exit 1
}

# Copy to repo root (for when you build the installer later)
Copy-Item $exe (Join-Path $root "flez-bot.exe") -Force
Write-Host "Copied to repo root (flez-bot.exe)." -ForegroundColor Green

# Copy to default install dir if it exists (quick test without reinstalling)
$installDir = Join-Path $env:LOCALAPPDATA "flez-bot"
if (Test-Path $installDir) {
    Copy-Item $exe (Join-Path $installDir "flez-bot.exe") -Force
    Write-Host "Copied to install dir: $installDir" -ForegroundColor Green
    if (-not $NoLaunch) {
        Write-Host "Launching..." -ForegroundColor Cyan
        Start-Process (Join-Path $installDir "flez-bot.exe") -WorkingDirectory $installDir
    }
} else {
    Write-Host "Install dir not found ($installDir). Run the setup exe once, or build the installer and install." -ForegroundColor Yellow
}

Write-Host "Done." -ForegroundColor Green
