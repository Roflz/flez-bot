param()

$ErrorActionPreference = "Stop"

Write-Host "download-installers.ps1 is deprecated in bootstrap-installer mode." -ForegroundColor Yellow
Write-Host "No local Python/Git installers are required for setup.exe anymore." -ForegroundColor Yellow
Write-Host "Use .\bundle-setup.ps1 to build setup.exe and .\build-release-artifacts.ps1 for app-full artifacts." -ForegroundColor Cyan
