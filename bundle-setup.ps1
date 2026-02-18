# Build FlezBotSetup.exe: launcher exe, release artifacts, then Inno Setup bootstrap installer.
# Run from flez-bot repo root: .\bundle-setup.ps1

param(
    [string]$Channel = "alpha",
    [string]$ReleaseBaseUrl = "https://github.com/Roflz/flez-bot/releases/download/latest",
    [string]$Version
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
if (-not $root) { $root = Get-Location }

Set-Location $root

function Resolve-ReleaseVersion {
    param([string]$InputVersion)

    $value = ""
    if ($InputVersion) {
        $value = $InputVersion.Trim()
    } else {
        $tag = & git describe --tags --exact-match 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $tag) {
            throw "No exact git tag found at HEAD. Release builds must run from a tag (e.g. v1.2.3 or v1.2.3-alpha.1), or pass -Version explicitly for non-release testing."
        }
        $value = $tag.Trim()
    }

    if ($value.StartsWith("v")) {
        $value = $value.Substring(1)
    }
    if ($value -notmatch '^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$') {
        throw ("Invalid release version '" + $value + "'. Expected MAJOR.MINOR.PATCH or MAJOR.MINOR.PATCH-prerelease.")
    }
    return $value
}

$resolvedVersion = Resolve-ReleaseVersion -InputVersion $Version
Write-Host ("Resolved release version: " + $resolvedVersion) -ForegroundColor Green
Write-Host ""

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
Write-Host "  Step 2/4: Build app-full release artifacts" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
& "$root\build-release-artifacts.ps1" -Channel $Channel -ReleaseBaseUrl $ReleaseBaseUrl -Version $resolvedVersion
if ($LASTEXITCODE -ne 0) { throw "build-release-artifacts.ps1 failed." }
Write-Host ""

Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "  Step 3/4: Build installer (Inno Setup)" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
& iscc "/DMyAppVersion=$resolvedVersion" installer.iss
if ($LASTEXITCODE -ne 0) { throw "iscc failed." }
Write-Host ""

Write-Host "Done. Setup exe: dist\FlezBotSetup.exe" -ForegroundColor Green
