# Build setup.exe: launcher exe, bundled Git/Python installers, then Inno Setup.
# Run from flez-bot repo root: .\bundle-setup.ps1

param(
    [switch]$ForceInstallerDownload
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
if (-not $root) { $root = Get-Location }

Set-Location $root

Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "  Step 0/4: Generate packaging/icon.ico" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
& python packaging/make_icon.py
if ($LASTEXITCODE -ne 0) { throw "make_icon.py failed." }
Write-Host ""

Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "  Step 1/4: Build flez-bot.exe (PyInstaller)" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
& python -m PyInstaller flez-bot.spec
if ($LASTEXITCODE -ne 0) { throw "PyInstaller failed." }
Copy-Item -Path "dist\flez-bot.exe" -Destination ".\flez-bot.exe" -Force
Write-Host "  flez-bot.exe copied to repo root." -ForegroundColor Green
Write-Host ""

Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "  Step 2/4: Ensure Git and Python installers" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
if ($ForceInstallerDownload) {
    & "$root\installer_deps\download-installers.ps1" -ForceDownload
} else {
    & "$root\installer_deps\download-installers.ps1"
}
if ($LASTEXITCODE -ne 0) { throw "Download installers failed." }
Write-Host ""

Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "  Step 3/4: Build installer (Inno Setup)" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
& iscc installer.iss
if ($LASTEXITCODE -ne 0) { throw "iscc failed." }
Write-Host ""

Write-Host "Done. Setup exe: dist\setup.exe" -ForegroundColor Green
