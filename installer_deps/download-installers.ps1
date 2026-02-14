# Downloads official Git and Python installers into this folder for bundling in setup.exe.
# Run from repo root: .\installer_deps\download-installers.ps1
# Existing installer files are reused by default; use -ForceDownload to refresh.

param(
    [switch]$ForceDownload
)

$ErrorActionPreference = "Stop"
$depsDir = $PSScriptRoot

# Git for Windows 64-bit (pinned version)
$gitUrl = "https://github.com/git-for-windows/git/releases/download/v2.43.0.windows.1/Git-2.43.0-64-bit.exe"
$gitOut = Join-Path $depsDir "GitInstaller.exe"

# Python 3.13 64-bit (pinned version)
$pythonUrl = "https://www.python.org/ftp/python/3.13.0/python-3.13.0-amd64.exe"
$pythonOut = Join-Path $depsDir "PythonInstaller.exe"

function Ensure-InstallerFile {
    param(
        [string]$Label,
        [string]$Url,
        [string]$OutFilePath
    )

    $sourceMarker = "$OutFilePath.source-url.txt"
    $hasMatchingSource = $false
    if ((Test-Path $OutFilePath) -and (Test-Path $sourceMarker)) {
        $existingSource = (Get-Content -Path $sourceMarker -Raw -ErrorAction SilentlyContinue).Trim()
        if ($existingSource -eq $Url) {
            $hasMatchingSource = $true
        }
    }

    if ((-not $ForceDownload) -and $hasMatchingSource) {
        Write-Host "$Label installer already present and up to date, reusing: $OutFilePath"
        return
    }

    Write-Host "Downloading $Label installer..."
    Invoke-WebRequest -Uri $Url -OutFile $OutFilePath -UseBasicParsing
    Set-Content -Path $sourceMarker -Value $Url -Encoding ASCII
}

Ensure-InstallerFile -Label "Git for Windows" -Url $gitUrl -OutFilePath $gitOut
Ensure-InstallerFile -Label "Python 3.13" -Url $pythonUrl -OutFilePath $pythonOut

Write-Host "Done. GitInstaller.exe and PythonInstaller.exe are in installer_deps."
Write-Host "You can now run: iscc installer.iss (or iscc /DBUNDLE_DIR=dist\flez-bot-bundle installer.iss)"
