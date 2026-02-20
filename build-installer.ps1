param(
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
            throw "No exact git tag found at HEAD. Pass -Version explicitly or run from a tagged commit."
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

function Test-PythonAvailable {
    & python --version | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "python is required but was not found in PATH."
    }
}

function Install-PyInstallerIfMissing {
    & python -m PyInstaller --version | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "PyInstaller already installed." -ForegroundColor DarkGray
        return
    }

    Write-Host "Installing PyInstaller..." -ForegroundColor Yellow
    & python -m pip install --upgrade pip
    if ($LASTEXITCODE -ne 0) { throw "Failed to upgrade pip." }
    & python -m pip install pyinstaller
    if ($LASTEXITCODE -ne 0) { throw "Failed to install PyInstaller." }
}

function Resolve-IsccPath {
    $cmd = Get-Command iscc -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $candidates = @(
        "$env:ProgramFiles(x86)\Inno Setup 6\ISCC.exe",
        "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) {
            return $candidate
        }
    }

    return $null
}

function Install-InnoSetupIfMissing {
    $iscc = Resolve-IsccPath
    if ($iscc) {
        Write-Host ("Inno Setup found: " + $iscc) -ForegroundColor DarkGray
        return $iscc
    }

    if (Get-Command choco -ErrorAction SilentlyContinue) {
        Write-Host "Installing Inno Setup via Chocolatey..." -ForegroundColor Yellow
        & choco install innosetup --no-progress -y
        if ($LASTEXITCODE -ne 0) { throw "Chocolatey failed to install Inno Setup." }
        $iscc = Resolve-IsccPath
        if ($iscc) { return $iscc }
    }

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "Installing Inno Setup via winget..." -ForegroundColor Yellow
        & winget install --id JRSoftware.InnoSetup -e --accept-source-agreements --accept-package-agreements
        if ($LASTEXITCODE -ne 0) { throw "winget failed to install Inno Setup." }
        $iscc = Resolve-IsccPath
        if ($iscc) { return $iscc }
    }

    throw "Inno Setup (ISCC.exe) not found after bootstrap attempts."
}

$resolvedVersion = Resolve-ReleaseVersion -InputVersion $Version
Write-Host ("Resolved release version: " + $resolvedVersion) -ForegroundColor Green
Write-Host ""

Test-PythonAvailable
Install-PyInstallerIfMissing
$isccPath = Install-InnoSetupIfMissing

Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "  Step 1/3: Generate packaging/icon.ico" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
& python packaging/make_icon.py
if ($LASTEXITCODE -ne 0) { throw "make_icon.py failed." }
Write-Host ""

Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "  Step 2/3: Build flez-bot.exe (PyInstaller)" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
& python -m PyInstaller flez-bot.spec
if ($LASTEXITCODE -ne 0) { throw "PyInstaller failed." }
Copy-Item -Path "dist\flez-bot.exe" -Destination ".\flez-bot.exe" -Force
Write-Host "  flez-bot.exe copied to repo root." -ForegroundColor Green
Write-Host ""

Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "  Step 3/3: Build installer (Inno Setup)" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
& $isccPath "/DMyAppVersion=$resolvedVersion" installer.iss
if ($LASTEXITCODE -ne 0) { throw "iscc failed." }
Write-Host ""

Write-Host "Done. Setup exe: dist\FlezBotSetup.exe" -ForegroundColor Green
