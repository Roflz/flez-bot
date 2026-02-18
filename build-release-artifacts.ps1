param(
    [string]$Channel = "alpha",
    [string]$ReleaseBaseUrl = "https://github.com/Roflz/flez-bot/releases/download/latest",
    [string]$Version,
    [switch]$RebuildRuntime
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
if (-not $root) { $root = Get-Location }
Set-Location $root

$distDir = Join-Path $root "dist"
$releaseStage = Join-Path $distDir "app-full-stage"
$artifactPath = Join-Path $distDir "app-full.zip"
$manifestPath = Join-Path $distDir "manifest.json"
$artifactShaPath = Join-Path $distDir "app-full.zip.sha256"
$manifestShaPath = Join-Path $distDir "manifest.json.sha256"
$runtimeRoot = Join-Path $root "runtime\python"
$runtimePython = Join-Path $runtimeRoot "python.exe"
$pythonEmbedZip = Join-Path $root "installer_deps\PythonEmbed.zip"
$getPipScript = Join-Path $root "installer_deps\get-pip.py"
$rootRequirements = Join-Path $root "requirements.txt"
$botRequirements = Join-Path $root "bot_runelite_IL\requirements.txt"

function Write-Step {
    param([string]$Message)
    Write-Host ("[build-release-artifacts] " + $Message) -ForegroundColor Cyan
}

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments = @()
    )
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw ("Command failed (" + $LASTEXITCODE + "): " + $FilePath + " " + ($Arguments -join " "))
    }
}

function Update-EmbeddedPythonPathFile {
    param([Parameter(Mandatory = $true)][string]$PythonRoot)
    $pthFile = Get-ChildItem -Path $PythonRoot -Filter "python*._pth" -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $pthFile) {
        throw "No python*._pth file found in embedded runtime."
    }

    $existing = Get-Content -Path $pthFile.FullName -ErrorAction SilentlyContinue
    $updated = New-Object System.Collections.Generic.List[string]
    $hasLib = $false
    $hasSitePackages = $false

    foreach ($line in $existing) {
        $trimmed = $line.Trim()
        if ($trimmed -eq "#import site" -or $trimmed -eq "import site") {
            continue
        }
        if ($trimmed -match '^(\\|\.\\)?Lib$') { $hasLib = $true }
        if ($trimmed -match '^(\\|\.\\)?Lib\\site-packages$') { $hasSitePackages = $true }
        $updated.Add($line)
    }
    if (-not $hasLib) { $updated.Add("Lib") }
    if (-not $hasSitePackages) { $updated.Add("Lib\site-packages") }
    $updated.Add("import site")
    Set-Content -Path $pthFile.FullName -Value $updated -Encoding ASCII
}

function Ensure-EmbeddedRuntime {
    if ((-not $RebuildRuntime) -and (Test-Path $runtimePython)) {
        Write-Step "Embedded runtime already present: $runtimePython"
        return
    }

    if (-not (Test-Path $pythonEmbedZip)) {
        throw "Missing embedded runtime zip: $pythonEmbedZip"
    }
    if (-not (Test-Path $getPipScript)) {
        throw "Missing get-pip script: $getPipScript"
    }

    Write-Step "Provisioning embedded runtime..."
    if (Test-Path $runtimeRoot) {
        Remove-Item -Path $runtimeRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Force -Path $runtimeRoot | Out-Null
    Expand-Archive -Path $pythonEmbedZip -DestinationPath $runtimeRoot -Force

    Update-EmbeddedPythonPathFile -PythonRoot $runtimeRoot

    Write-Step "Bootstrapping pip in embedded runtime..."
    Invoke-Checked -FilePath $runtimePython -Arguments @($getPipScript, "--no-warn-script-location")
    Invoke-Checked -FilePath $runtimePython -Arguments @("-m", "pip", "--version")

    $env:PIP_DISABLE_PIP_VERSION_CHECK = "1"

    if (Test-Path $rootRequirements) {
        Write-Step "Installing root requirements into embedded runtime..."
        Invoke-Checked -FilePath $runtimePython -Arguments @("-m", "pip", "install", "-r", $rootRequirements, "--prefer-binary", "--no-build-isolation", "--no-warn-script-location")
    }
    if (Test-Path $botRequirements) {
        Write-Step "Installing bot requirements into embedded runtime..."
        Invoke-Checked -FilePath $runtimePython -Arguments @("-m", "pip", "install", "-r", $botRequirements, "--prefer-binary", "--no-build-isolation", "--no-warn-script-location")
    }

    Write-Step "Embedded runtime ready."
}

if (Test-Path $releaseStage) { Remove-Item -Path $releaseStage -Recurse -Force }
New-Item -ItemType Directory -Force -Path $releaseStage | Out-Null
New-Item -ItemType Directory -Force -Path $distDir | Out-Null

if (-not $Version) {
    throw "Version is required. Pass -Version from a validated SemVer tag (e.g. 1.2.3 or 1.2.3-alpha.1)."
}
$version = $Version.Trim()
if ($version.StartsWith("v")) {
    $version = $version.Substring(1)
}
if ($version -notmatch '^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$') {
    throw ("Invalid SemVer version: " + $Version + ". Expected MAJOR.MINOR.PATCH or MAJOR.MINOR.PATCH-prerelease.")
}

Ensure-EmbeddedRuntime

$required = @(
    "runtime\python\python.exe",
    "bot_runelite_IL\gui_pyside.py"
)
foreach ($rel in $required) {
    $full = Join-Path $root $rel
    if (-not (Test-Path $full)) {
        throw ("Required runtime payload missing for app-full.zip: " + $full)
    }
}

$copyItems = @(
    "runtime",
    "bot_runelite_IL",
    "runelite",
    "web",
    "version.json",
    ".env.example"
)
foreach ($item in $copyItems) {
    $src = Join-Path $root $item
    if (Test-Path $src) {
        Copy-Item -Path $src -Destination $releaseStage -Recurse -Force
    }
}

$versionJsonPath = Join-Path $releaseStage "version.json"
if (-not (Test-Path $versionJsonPath)) {
    $versionJsonText = @{ version = $version } | ConvertTo-Json
    Write-Utf8NoBom -Path $versionJsonPath -Content ($versionJsonText + "`n")
}

if (Test-Path $artifactPath) { Remove-Item -Path $artifactPath -Force }
Compress-Archive -Path (Join-Path $releaseStage "*") -DestinationPath $artifactPath -Force

$artifactHash = (Get-FileHash -Path $artifactPath -Algorithm SHA256).Hash.ToLowerInvariant()
$artifactSize = (Get-Item $artifactPath).Length

Set-Content -Path $artifactShaPath -Value ($artifactHash + "  app-full.zip") -Encoding ASCII

$manifest = @{
    schemaVersion = 1
    minUpdaterVersion = 1
    version = $version
    channel = $Channel
    artifacts = @(
        @{
            name = "app-full.zip"
            type = "full"
            url = ($ReleaseBaseUrl.TrimEnd("/") + "/app-full.zip")
            sizeBytes = $artifactSize
            sha256 = $artifactHash
        }
    )
}
$manifestText = $manifest | ConvertTo-Json -Depth 8
Write-Utf8NoBom -Path $manifestPath -Content ($manifestText + "`n")
$manifestHash = (Get-FileHash -Path $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -Path $manifestShaPath -Value ($manifestHash + "  manifest.json") -Encoding ASCII

Write-Host "Release artifacts generated:" -ForegroundColor Green
Write-Host " - dist\app-full.zip"
Write-Host " - dist\app-full.zip.sha256"
Write-Host " - dist\manifest.json"
Write-Host " - dist\manifest.json.sha256"
