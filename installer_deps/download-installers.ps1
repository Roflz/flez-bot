# Downloads official Git and Python installers into this folder for bundling in setup.exe.
# Run from repo root: .\installer_deps\download-installers.ps1

$ErrorActionPreference = "Stop"
$depsDir = $PSScriptRoot

# Git for Windows 64-bit (pinned version)
$gitUrl = "https://github.com/git-for-windows/git/releases/download/v2.43.0.windows.1/Git-2.43.0-64-bit.exe"
$gitOut = Join-Path $depsDir "GitInstaller.exe"

# Python 3.13 64-bit (pinned version)
$pythonUrl = "https://www.python.org/ftp/python/3.13.0/python-3.13.0-amd64.exe"
$pythonOut = Join-Path $depsDir "PythonInstaller.exe"

Write-Host "Downloading Git for Windows..."
Invoke-WebRequest -Uri $gitUrl -OutFile $gitOut -UseBasicParsing

Write-Host "Downloading Python 3.13..."
Invoke-WebRequest -Uri $pythonUrl -OutFile $pythonOut -UseBasicParsing

Write-Host "Done. GitInstaller.exe and PythonInstaller.exe are in installer_deps."
Write-Host "You can now run: iscc installer.iss (or iscc /DBUNDLE_DIR=dist\flez-bot-bundle installer.iss)"
