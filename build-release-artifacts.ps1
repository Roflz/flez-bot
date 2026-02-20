param(
    [string]$Channel = "alpha",
    [string]$ReleaseBaseUrl = "https://github.com/Roflz/flez-bot/releases/download/latest",
    [string]$Version,
    [switch]$RebuildRuntime,
    [switch]$Incremental,
    [ValidateSet("auto", "7z", "builtin")][string]$ArchiveBackend = "auto",
    [int]$HeartbeatSeconds = 15
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
$incrementalStatePath = Join-Path $distDir "app-full.incremental.json"
$archiveStatsPath = Join-Path $distDir "app-full.archive-stats.json"
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

function Format-Duration {
    param([timespan]$Duration)
    return "{0:N1}s" -f $Duration.TotalSeconds
}

function Format-Bytes {
    param([double]$Bytes)
    if ($Bytes -ge 1GB) { return ("{0:N2} GB" -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ("{0:N2} MB" -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ("{0:N2} KB" -f ($Bytes / 1KB)) }
    return ("{0:N0} B" -f $Bytes)
}

function Format-Rate {
    param([double]$BytesPerSecond)
    return ((Format-Bytes -Bytes $BytesPerSecond) + "/s")
}

function Invoke-Phase {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Action
    )
    Write-Step (">>> " + $Name)
    $phaseTimer = [System.Diagnostics.Stopwatch]::StartNew()
    & $Action
    $phaseTimer.Stop()
    Write-Step ("<<< " + $Name + " completed in " + (Format-Duration -Duration $phaseTimer.Elapsed))
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

function Get-StringSha256 {
    param([Parameter(Mandatory = $true)][string]$Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        $hash = $sha.ComputeHash($bytes)
    } finally {
        $sha.Dispose()
    }
    return (($hash | ForEach-Object { $_.ToString("x2") }) -join "")
}

function Resolve-ArchiveBackend {
    param([Parameter(Mandatory = $true)][string]$RequestedBackend)
    $sevenZip = Find-SevenZipExecutable
    if ($RequestedBackend -eq "7z") {
        if (-not $sevenZip) {
            throw "Archive backend '7z' requested, but 7z/7za was not found (PATH or common install locations)."
        }
        return "7z"
    }
    if ($RequestedBackend -eq "builtin") {
        return "builtin"
    }
    if ($sevenZip) {
        return "7z"
    }
    return "builtin"
}

function Find-SevenZipExecutable {
    $cmd = Get-Command 7z -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $cmd = Get-Command 7za -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $commonPaths = @(
        "$env:ProgramFiles\7-Zip\7z.exe",
        "$env:ProgramFiles\7-Zip\7za.exe",
        "${env:ProgramFiles(x86)}\7-Zip\7z.exe",
        "${env:ProgramFiles(x86)}\7-Zip\7za.exe"
    )
    foreach ($path in $commonPaths) {
        if ($path -and (Test-Path $path)) {
            return $path
        }
    }
    return $null
}

function Get-CopyStats {
    param([Parameter(Mandatory = $true)][string]$Path)
    $files = Get-ChildItem -Path $Path -File -Recurse -ErrorAction SilentlyContinue
    $count = ($files | Measure-Object).Count
    $bytes = ($files | Measure-Object Length -Sum).Sum
    if (-not $bytes) { $bytes = 0 }
    return @{
        fileCount = [int]$count
        totalBytes = [double]$bytes
    }
}

function Copy-DirectoryWithProgress {
    param(
        [Parameter(Mandatory = $true)][string]$SourceDir,
        [Parameter(Mandatory = $true)][string]$DestinationParentDir,
        [Parameter(Mandatory = $true)][int]$HeartbeatIntervalSeconds
    )
    $dirName = Split-Path -Path $SourceDir -Leaf
    $destDir = Join-Path $DestinationParentDir $dirName
    if (Test-Path $destDir) {
        Remove-Item -Path $destDir -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null

    $stats = Get-CopyStats -Path $SourceDir
    Write-Step ("Copying directory '{0}' to '{1}' ({2} files, {3})" -f $SourceDir, $destDir, $stats.fileCount, (Format-Bytes -Bytes $stats.totalBytes))
    if ($stats.fileCount -eq 0) {
        return @{
            fileCount = 0
            totalBytes = 0
        }
    }

    $files = Get-ChildItem -Path $SourceDir -File -Recurse | Sort-Object FullName
    $copiedFiles = 0
    $copiedBytes = [double]0
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $nextHeartbeat = [double]$HeartbeatIntervalSeconds
    foreach ($file in $files) {
        $relativePath = $file.FullName.Substring($SourceDir.Length).TrimStart('\', '/')
        $destFile = Join-Path $destDir $relativePath
        $destFileDir = Split-Path -Path $destFile -Parent
        if (-not (Test-Path $destFileDir)) {
            New-Item -ItemType Directory -Force -Path $destFileDir | Out-Null
        }
        Copy-Item -Path $file.FullName -Destination $destFile -Force
        $copiedFiles += 1
        $copiedBytes += [double]$file.Length

        if ($timer.Elapsed.TotalSeconds -ge $nextHeartbeat) {
            Write-Step ("copy heartbeat [{0}] {1}/{2} files ({3}/{4}) elapsed={5}" -f $dirName, $copiedFiles, $stats.fileCount, (Format-Bytes -Bytes $copiedBytes), (Format-Bytes -Bytes $stats.totalBytes), (Format-Duration -Duration $timer.Elapsed))
            $nextHeartbeat += [double]$HeartbeatIntervalSeconds
        }
    }
    $timer.Stop()
    Write-Step ("Completed copy [{0}] {1} files ({2}) in {3}" -f $dirName, $copiedFiles, (Format-Bytes -Bytes $copiedBytes), (Format-Duration -Duration $timer.Elapsed))
    return @{
        fileCount = $copiedFiles
        totalBytes = [double]$copiedBytes
    }
}

function Compress-WithBuiltinHeartbeat {
    param(
        [Parameter(Mandatory = $true)][string]$SourceDir,
        [Parameter(Mandatory = $true)][string]$DestinationZip,
        [Parameter(Mandatory = $true)][int]$HeartbeatIntervalSeconds,
        [Parameter(Mandatory = $true)][double]$EstimatedTargetBytes
    )
    $job = Start-Job -ScriptBlock {
        param($InnerSourceDir, $InnerDestinationZip)
        Compress-Archive -Path (Join-Path $InnerSourceDir "*") -DestinationPath $InnerDestinationZip -Force
    } -ArgumentList $SourceDir, $DestinationZip

    try {
        $timer = [System.Diagnostics.Stopwatch]::StartNew()
        $nextHeartbeat = [double]$HeartbeatIntervalSeconds
        while ($true) {
            $current = Get-Job -Id $job.Id
            if (-not $current) {
                throw "Compression job disappeared unexpectedly."
            }
            if ($current.State -ne "Running" -and $current.State -ne "NotStarted") {
                break
            }
            Start-Sleep -Milliseconds 1000
            if ($timer.Elapsed.TotalSeconds -ge $nextHeartbeat) {
                $zipSize = 0
                if (Test-Path $DestinationZip) {
                    $zipSize = [double](Get-Item -Path $DestinationZip).Length
                }
                $pct = 0
                $etaText = "unknown"
                $rate = 0
                if ($EstimatedTargetBytes -gt 0) {
                    $pct = [math]::Floor([math]::Min(99, ($zipSize / $EstimatedTargetBytes) * 100))
                }
                if ($timer.Elapsed.TotalSeconds -gt 0) {
                    $rate = $zipSize / $timer.Elapsed.TotalSeconds
                    if ($rate -gt 0 -and $EstimatedTargetBytes -gt $zipSize) {
                        $remainingSeconds = ($EstimatedTargetBytes - $zipSize) / $rate
                        $etaText = (Format-Duration -Duration ([timespan]::FromSeconds($remainingSeconds)))
                    } elseif ($EstimatedTargetBytes -le $zipSize) {
                        $etaText = "soon"
                    }
                }
                Write-Step ("compression progress [builtin] est={0}% zip={1} rate={2} eta={3} elapsed={4}" -f $pct, (Format-Bytes -Bytes $zipSize), (Format-Rate -BytesPerSecond $rate), $etaText, (Format-Duration -Duration $timer.Elapsed))
                $nextHeartbeat += [double]$HeartbeatIntervalSeconds
            }
        }
        Receive-Job -Id $job.Id -ErrorAction Stop | Out-Null
        $finalJob = Get-Job -Id $job.Id
        if (-not $finalJob -or $finalJob.State -ne "Completed") {
            throw "Compress-Archive job did not complete successfully."
        }
        Write-Step "compression progress [builtin] est=100% eta=0.0s elapsed complete"
    } finally {
        if (Get-Job -Id $job.Id -ErrorAction SilentlyContinue) {
            Remove-Job -Id $job.Id -Force -ErrorAction SilentlyContinue
        }
    }
}

function Compress-WithSevenZip {
    param(
        [Parameter(Mandatory = $true)][string]$SourceDir,
        [Parameter(Mandatory = $true)][string]$DestinationZip
    )
    $sevenZip = Find-SevenZipExecutable
    if (-not $sevenZip) {
        throw "7z backend requested but 7z/7za executable not found."
    }

    Push-Location $SourceDir
    try {
        & $sevenZip "a" "-tzip" "-mx=5" "-bsp1" "-bso1" "-bse1" $DestinationZip ".\*"
        if ($LASTEXITCODE -ne 0) {
            throw ("7z archive creation failed with exit code " + $LASTEXITCODE)
        }
    } finally {
        Pop-Location
    }
}

function Get-EstimatedArchiveTargetBytes {
    param(
        [Parameter(Mandatory = $true)][double]$SourceBytes,
        [Parameter(Mandatory = $true)][string]$StatsPath
    )
    $ratio = 0.70
    if (Test-Path $StatsPath) {
        try {
            $stats = Get-Content -Path $StatsPath -Raw | ConvertFrom-Json
            if ($stats -and $stats.compressionRatio) {
                $r = [double]$stats.compressionRatio
                if ($r -ge 0.10 -and $r -le 1.20) {
                    $ratio = $r
                }
            }
        } catch {
            # Keep default estimate when stats file is unreadable.
        }
    }
    $estimate = [math]::Ceiling([math]::Max(1MB, ($SourceBytes * $ratio)))
    return [double]$estimate
}

function Save-ArchiveStats {
    param(
        [Parameter(Mandatory = $true)][string]$StatsPath,
        [Parameter(Mandatory = $true)][double]$SourceBytes,
        [Parameter(Mandatory = $true)][double]$ZipBytes,
        [Parameter(Mandatory = $true)][string]$Backend
    )
    if ($SourceBytes -le 0 -or $ZipBytes -le 0) { return }
    $ratio = $ZipBytes / $SourceBytes
    $stats = @{
        sourceBytes = [math]::Round($SourceBytes)
        zipBytes = [math]::Round($ZipBytes)
        compressionRatio = $ratio
        backend = $Backend
        updatedUtc = (Get-Date).ToUniversalTime().ToString("o")
    } | ConvertTo-Json
    Write-Utf8NoBom -Path $StatsPath -Content ($stats + "`n")
}

function Get-PayloadFingerprint {
    param(
        [Parameter(Mandatory = $true)][string]$RootDir,
        [Parameter(Mandatory = $true)][string[]]$PayloadItems
    )
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($item in $PayloadItems) {
        $full = Join-Path $RootDir $item
        if (-not (Test-Path $full)) {
            continue
        }
        $entry = Get-Item -Path $full -ErrorAction Stop
        if ($entry.PSIsContainer) {
            $files = Get-ChildItem -Path $full -File -Recurse -ErrorAction SilentlyContinue | Sort-Object FullName
            foreach ($file in $files) {
                $relative = $file.FullName.Substring($RootDir.Length).TrimStart('\', '/')
                $lines.Add(($relative + "|" + $file.Length + "|" + $file.LastWriteTimeUtc.Ticks))
            }
        } else {
            $relativeFile = $entry.FullName.Substring($RootDir.Length).TrimStart('\', '/')
            $lines.Add(($relativeFile + "|" + $entry.Length + "|" + $entry.LastWriteTimeUtc.Ticks))
        }
    }
    $payloadText = [string]::Join("`n", $lines)
    $fingerprint = Get-StringSha256 -Text $payloadText
    return @{
        hash = $fingerprint
        entryCount = $lines.Count
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

if ($HeartbeatSeconds -lt 1) {
    throw "HeartbeatSeconds must be >= 1."
}

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

$selectedArchiveBackend = Resolve-ArchiveBackend -RequestedBackend $ArchiveBackend
$totalTimer = [System.Diagnostics.Stopwatch]::StartNew()
Write-Step ("Resolved archive backend: " + $selectedArchiveBackend)
if ($ArchiveBackend -eq "auto" -and $selectedArchiveBackend -eq "builtin") {
    Write-Step "7-Zip not found (checked PATH and common install locations). Falling back to Compress-Archive."
    Write-Step "Tip: install 7-Zip and rerun with -ArchiveBackend auto or -ArchiveBackend 7z for faster, more verbose zip progress."
}
Write-Step ("Incremental mode: " + ($(if ($Incremental.IsPresent) { "enabled" } else { "disabled" })))
Write-Step ("Heartbeat interval: " + $HeartbeatSeconds + "s")

Invoke-Phase -Name "Runtime ensure/provision" -Action {
    Ensure-EmbeddedRuntime
}

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
$expectedOutputs = @(
    $artifactPath,
    $artifactShaPath,
    $manifestPath,
    $manifestShaPath
)
$payloadFingerprint = $null
$skipHeavyBuild = $false

if ($Incremental.IsPresent) {
    Invoke-Phase -Name "Compute incremental fingerprint" -Action {
        $payloadFingerprint = Get-PayloadFingerprint -RootDir $root -PayloadItems $copyItems
        Write-Step ("Incremental fingerprint computed: entries=" + $payloadFingerprint.entryCount)
    }

    $allOutputsExist = $true
    foreach ($output in $expectedOutputs) {
        if (-not (Test-Path $output)) {
            $allOutputsExist = $false
            break
        }
    }

    if ($allOutputsExist -and (Test-Path $incrementalStatePath)) {
        try {
            $previous = Get-Content -Path $incrementalStatePath -Raw | ConvertFrom-Json
            if ($previous -and $previous.fingerprint -eq $payloadFingerprint.hash) {
                $skipHeavyBuild = $true
                Write-Step "Incremental fingerprint unchanged and outputs present. Skipping recopy/rezip."
            } else {
                Write-Step "Incremental fingerprint changed. Running full copy/zip path."
            }
        } catch {
            Write-Step "Incremental state unreadable. Running full copy/zip path."
        }
    } else {
        Write-Step "Incremental state or outputs missing. Running full copy/zip path."
    }
}

if (-not $skipHeavyBuild) {
    Invoke-Phase -Name "Stage prep" -Action {
        if (Test-Path $releaseStage) {
            Remove-Item -Path $releaseStage -Recurse -Force
        }
        New-Item -ItemType Directory -Force -Path $releaseStage | Out-Null
        New-Item -ItemType Directory -Force -Path $distDir | Out-Null
    }

    Invoke-Phase -Name "Payload copy" -Action {
        $totalFiles = 0
        $totalBytes = [double]0
        foreach ($item in $copyItems) {
            $src = Join-Path $root $item
            if (-not (Test-Path $src)) {
                Write-Step ("Skipping missing payload item: " + $item)
                continue
            }
            $entry = Get-Item -Path $src
            if ($entry.PSIsContainer) {
                $result = Copy-DirectoryWithProgress -SourceDir $src -DestinationParentDir $releaseStage -HeartbeatIntervalSeconds $HeartbeatSeconds
                $totalFiles += [int]$result.fileCount
                $totalBytes += [double]$result.totalBytes
            } else {
                Write-Step ("Copying file '{0}' to '{1}'" -f $src, $releaseStage)
                Copy-Item -Path $src -Destination $releaseStage -Force
                $size = [double](Get-Item -Path $src).Length
                Write-Step ("Completed copy [{0}] {1}" -f $item, (Format-Bytes -Bytes $size))
                $totalFiles += 1
                $totalBytes += $size
            }
        }
        Write-Step ("Payload copy totals: files={0}, bytes={1}" -f $totalFiles, (Format-Bytes -Bytes $totalBytes))
        $script:stagedTotalBytes = $totalBytes
    }

    Invoke-Phase -Name "Ensure staged version metadata" -Action {
        $versionJsonPath = Join-Path $releaseStage "version.json"
        if (-not (Test-Path $versionJsonPath)) {
            $versionJsonText = @{ version = $version } | ConvertTo-Json
            Write-Utf8NoBom -Path $versionJsonPath -Content ($versionJsonText + "`n")
        }
    }

    Invoke-Phase -Name "Archive build" -Action {
        if (Test-Path $artifactPath) {
            Remove-Item -Path $artifactPath -Force
        }
        $estimatedZipBytes = Get-EstimatedArchiveTargetBytes -SourceBytes $script:stagedTotalBytes -StatsPath $archiveStatsPath
        Write-Step ("Archive estimate: target zip size ~{0} based on stage size {1}" -f (Format-Bytes -Bytes $estimatedZipBytes), (Format-Bytes -Bytes $script:stagedTotalBytes))
        if ($selectedArchiveBackend -eq "7z") {
            Write-Step "Building app-full.zip with 7z backend..."
            Compress-WithSevenZip -SourceDir $releaseStage -DestinationZip $artifactPath
        } else {
            Write-Step "Building app-full.zip with Compress-Archive backend..."
            Compress-WithBuiltinHeartbeat -SourceDir $releaseStage -DestinationZip $artifactPath -HeartbeatIntervalSeconds $HeartbeatSeconds -EstimatedTargetBytes $estimatedZipBytes
        }
        $archiveBytes = [double](Get-Item -Path $artifactPath).Length
        Save-ArchiveStats -StatsPath $archiveStatsPath -SourceBytes $script:stagedTotalBytes -ZipBytes $archiveBytes -Backend $selectedArchiveBackend
    }

    if ($Incremental.IsPresent) {
        if (-not $payloadFingerprint) {
            $payloadFingerprint = Get-PayloadFingerprint -RootDir $root -PayloadItems $copyItems
        }
        $state = @{
            fingerprint = $payloadFingerprint.hash
            entryCount = $payloadFingerprint.entryCount
            updatedUtc = (Get-Date).ToUniversalTime().ToString("o")
        } | ConvertTo-Json
        Write-Utf8NoBom -Path $incrementalStatePath -Content ($state + "`n")
        Write-Step "Incremental state updated."
    }
}

Invoke-Phase -Name "Hash + manifest generation" -Action {
    if (-not (Test-Path $artifactPath)) {
        throw ("Expected artifact missing: " + $artifactPath)
    }

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
}

$totalTimer.Stop()
Write-Step ("Total elapsed: " + (Format-Duration -Duration $totalTimer.Elapsed))
Write-Host "Release artifacts generated:" -ForegroundColor Green
Write-Host " - dist\app-full.zip"
Write-Host " - dist\app-full.zip.sha256"
Write-Host " - dist\manifest.json"
Write-Host " - dist\manifest.json.sha256"
