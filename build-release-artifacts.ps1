param(
    [string]$Channel = "alpha",
    [string]$ReleaseBaseUrl = "https://github.com/Roflz/flez-bot/releases/download/latest"
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

if (Test-Path $releaseStage) { Remove-Item -Path $releaseStage -Recurse -Force }
New-Item -ItemType Directory -Force -Path $releaseStage | Out-Null
New-Item -ItemType Directory -Force -Path $distDir | Out-Null

$version = (Get-Content -Raw -Path (Join-Path $root "app_version.txt")).Trim()
if (-not $version) { throw "app_version.txt is empty." }

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
    @{ version = $version } | ConvertTo-Json | Set-Content -Path $versionJsonPath -Encoding UTF8
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
$manifest | ConvertTo-Json -Depth 8 | Set-Content -Path $manifestPath -Encoding UTF8
$manifestHash = (Get-FileHash -Path $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -Path $manifestShaPath -Value ($manifestHash + "  manifest.json") -Encoding ASCII

Write-Host "Release artifacts generated:" -ForegroundColor Green
Write-Host " - dist\app-full.zip"
Write-Host " - dist\app-full.zip.sha256"
Write-Host " - dist\manifest.json"
Write-Host " - dist\manifest.json.sha256"
