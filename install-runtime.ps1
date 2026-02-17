param(
    [Parameter(Mandatory = $true)][string]$InstallDir,
    [string]$Channel = "alpha",
    [string]$ManifestUrl = ""
)

$ErrorActionPreference = "Stop"

$root = $InstallDir
$logsDir = Join-Path $root "logs"
New-Item -ItemType Directory -Force -Path $logsDir | Out-Null
$logPath = Join-Path $logsDir "install.log"
$prevLogPath = Join-Path $logsDir "install.previous.log"

if (Test-Path $prevLogPath) { Remove-Item $prevLogPath -Force -ErrorAction SilentlyContinue }
if (Test-Path $logPath) { Move-Item $logPath $prevLogPath -Force }
New-Item -ItemType File -Path $logPath -Force | Out-Null

function Write-InstallLog {
    param([string]$Message)
    $line = "{0} {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"), $Message
    Add-Content -Path $logPath -Value $line -Encoding UTF8
}

function Write-Phase {
    param([string]$Name)
    Write-InstallLog ("========== " + $Name + " ==========")
}

function Ensure-Layout {
    Write-Phase "Phase 1/5: Preparing install location"
    $dirs = @(
        "app_live",
        "app_stage",
        "app_backup",
        "state",
        "logs",
        "cache",
        "data",
        "tmp"
    )
    foreach ($d in $dirs) {
        $full = Join-Path $root $d
        New-Item -ItemType Directory -Force -Path $full | Out-Null
        Write-InstallLog ("DIR_READY: " + $full)
    }
}

function Get-LatestRelease {
    param([string]$ReleaseChannel)
    $apiUrl = "https://api.github.com/repos/Roflz/flez-bot/releases"
    Write-InstallLog ("FETCH_RELEASES: " + $apiUrl)
    $resp = Invoke-RestMethod -Uri $apiUrl -Headers @{ Accept = "application/vnd.github+json" }
    foreach ($rel in $resp) {
        $isPre = [bool]$rel.prerelease
        $tag = [string]$rel.tag_name
        if ($ReleaseChannel -eq "stable") {
            if (-not $isPre) { return $rel }
        } else {
            if ($isPre -or $tag.ToLower().Contains("alpha")) { return $rel }
        }
    }
    throw "No release found for channel '$ReleaseChannel'."
}

function Resolve-ManifestUrl {
    param([string]$ReleaseChannel, [string]$UserManifestUrl)
    if ($UserManifestUrl) {
        Write-InstallLog ("MANIFEST_URL_OVERRIDE: " + $UserManifestUrl)
        return $UserManifestUrl
    }
    $release = Get-LatestRelease -ReleaseChannel $ReleaseChannel
    foreach ($asset in $release.assets) {
        if ($asset.name -eq "manifest.json") {
            Write-InstallLog ("MANIFEST_URL_FROM_RELEASE: " + $asset.browser_download_url)
            return [string]$asset.browser_download_url
        }
    }
    throw "manifest.json not found on selected release."
}

function Download-FileWithProgress {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$OutFile,
        [string]$PhaseName = "Download"
    )

    Write-Phase $PhaseName
    Write-InstallLog ("DOWNLOAD_START: " + $Url)
    $request = [System.Net.HttpWebRequest]::Create($Url)
    $request.Method = "GET"
    $response = $request.GetResponse()
    $total = $response.ContentLength
    $stream = $response.GetResponseStream()
    $fileStream = [System.IO.File]::Create($OutFile)
    try {
        $buffer = New-Object byte[] (1024 * 1024)
        $read = 0
        $done = 0
        $lastPct = -1
        while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $fileStream.Write($buffer, 0, $read)
            $done += $read
            if ($total -gt 0) {
                $pct = [int](($done * 100) / $total)
                if ($pct -ne $lastPct) {
                    $lastPct = $pct
                    Write-InstallLog ("DOWNLOAD_PROGRESS: " + $pct + "% (" + $done + "/" + $total + " bytes)")
                }
            } else {
                Write-InstallLog ("DOWNLOAD_PROGRESS: " + $done + " bytes")
            }
        }
    }
    finally {
        if ($fileStream) { $fileStream.Dispose() }
        if ($stream) { $stream.Dispose() }
        if ($response) { $response.Dispose() }
    }
    Write-InstallLog ("DOWNLOAD_COMPLETE: " + $OutFile)
}

function Validate-AppStage {
    param([Parameter(Mandatory = $true)][string]$StageDir)
    Write-Phase "ValidateStage"
    $required = @(
        (Join-Path $StageDir "version.json"),
        (Join-Path $StageDir "runtime\python\python.exe"),
        (Join-Path $StageDir "bot_runelite_IL\gui_pyside.py")
    )
    foreach ($p in $required) {
        if (-not (Test-Path $p)) {
            throw ("Missing required staged file: " + $p)
        }
        Write-InstallLog ("VALIDATE_EXISTS_OK: " + $p)
    }
    Write-InstallLog "VALIDATE_APP_ENTRY_OK"
}

try {
    Write-Phase "Start"
    Write-InstallLog "=== flez-bot bootstrap install started ==="
    Write-InstallLog ("InstallDir: " + $InstallDir)
    Write-InstallLog ("Channel: " + $Channel)

    Ensure-Layout

    $cacheDir = Join-Path $root "cache"
    $manifestPath = Join-Path $cacheDir "manifest.json"
    $artifactPath = Join-Path $cacheDir "app-full.zip"
    $stageDir = Join-Path $root "app_stage"
    $liveDir = Join-Path $root "app_live"
    $backupDir = Join-Path $root "app_backup"
    $stateDir = Join-Path $root "state"
    $statePath = Join-Path $stateDir "state.json"

    $resolvedManifestUrl = Resolve-ManifestUrl -ReleaseChannel $Channel -UserManifestUrl $ManifestUrl
    Download-FileWithProgress -Url $resolvedManifestUrl -OutFile $manifestPath -PhaseName "Phase 2/5: Downloading release manifest"
    $manifest = Get-Content -Raw -Path $manifestPath | ConvertFrom-Json
    Write-InstallLog ("MANIFEST_VERSION: " + [string]$manifest.version)

    $artifact = $null
    foreach ($a in $manifest.artifacts) {
        if ($a.name -eq "app-full.zip" -and $a.type -eq "full") {
            $artifact = $a
            break
        }
    }
    if ($null -eq $artifact) {
        throw "Manifest missing app-full.zip full artifact entry."
    }
    if (-not $artifact.url -or -not $artifact.sha256) {
        throw "Artifact metadata missing url or sha256."
    }

    Download-FileWithProgress -Url ([string]$artifact.url) -OutFile $artifactPath -PhaseName "Phase 3/5: Downloading application package"

    Write-Phase "Phase 4/5: Verifying package integrity"
    $expectedSha = ([string]$artifact.sha256).ToLowerInvariant()
    $actualSha = (Get-FileHash -Path $artifactPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Write-InstallLog ("SHA_EXPECTED: " + $expectedSha)
    Write-InstallLog ("SHA_ACTUAL: " + $actualSha)
    if ($actualSha -ne $expectedSha) {
        throw "Artifact SHA256 mismatch."
    }
    Write-InstallLog "SHA_VERIFY_PASS"

    Write-Phase "ExtractToStage"
    if (Test-Path $stageDir) {
        Remove-Item -Path $stageDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Force -Path $stageDir | Out-Null
    Expand-Archive -Path $artifactPath -DestinationPath $stageDir -Force
    Write-InstallLog ("EXTRACT_COMPLETE: " + $stageDir)

    Validate-AppStage -StageDir $stageDir

    Write-Phase "Phase 5/5: Installing files and finalizing"
    if (Test-Path $backupDir) {
        Remove-Item -Path $backupDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $liveDir) {
        Move-Item -Path $liveDir -Destination $backupDir -Force
        Write-InstallLog ("MOVED_LIVE_TO_BACKUP: " + $backupDir)
    }
    Move-Item -Path $stageDir -Destination $liveDir -Force
    Write-InstallLog ("MOVED_STAGE_TO_LIVE: " + $liveDir)

    $version = "0.0.0"
    try {
        $verJson = Get-Content -Raw -Path (Join-Path $liveDir "version.json") | ConvertFrom-Json
        if ($verJson.version) { $version = [string]$verJson.version }
    } catch {}

    $stateObj = @{
        schemaVersion = 1
        channel = $Channel
        currentVersion = $version
        targetVersion = $null
        status = "idle"
        artifact = $null
        attempts = @{
            applyCount = 0
            rollbackCount = 0
        }
        timestamps = @{
            updatedAt = (Get-Date).ToUniversalTime().ToString("o")
            applyStartedAt = $null
        }
        lastError = $null
    }
    $stateObj | ConvertTo-Json -Depth 8 | Set-Content -Path $statePath -Encoding UTF8
    Write-InstallLog ("STATE_WRITTEN: " + $statePath)

    Write-Phase "Complete"
    Write-InstallLog "=== flez-bot bootstrap install completed successfully ==="
    exit 0
}
catch {
    Write-Phase "Failure"
    Write-InstallLog ("ERROR_MESSAGE: " + $_.Exception.Message)
    Write-InstallLog ("ERROR_DETAIL: " + ($_ | Out-String).Trim())
    Write-InstallLog "ACTION: Re-run installer or reinstall flez-bot. See this log for details."
    Write-InstallLog ("LOG_PATH: " + $logPath)
    Write-InstallLog "=== flez-bot bootstrap install failed ==="
    exit 1
}
