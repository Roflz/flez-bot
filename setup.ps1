<#
.SYNOPSIS
    Setup script for flez-bot. Installs and configures. No checks.

.DESCRIPTION
    Each action does one thing. Launcher performs prereq check and passes only needed actions.
    No flags = full setup (installer).

.PARAMETER UpdateRepos
    Fetch, submodule update, checkout main/master for umbrella and submodules.

.PARAMETER MergeRuneliteUpstream
    Merge latest runelite-parent-* release into runelite. Cleans hs_err_pid*.log first.

.PARAMETER InstallDep
    Install specific Python package(s). e.g. -InstallDep PySide6 -InstallDep psutil

.PARAMETER Update
    Fetch and update submodules (launcher's update step). Exits after.
#>

param(
    [switch]$UpdateRepos,
    [switch]$MergeRuneliteUpstream,
    [string[]]$InstallDep = @(),
    [switch]$Update
)

$ErrorActionPreference = "Stop"

function Write-Info  { Write-Host $args -ForegroundColor Cyan }
function Write-Success { Write-Host $args -ForegroundColor Green }
function Write-Warn  { Write-Host $args -ForegroundColor Yellow }
function Write-Err   { Write-Host $args -ForegroundColor Red }

$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) { $ScriptDir = Get-Location }

$botPath = Join-Path $ScriptDir "bot_runelite_IL"
$runelitePath = Join-Path $ScriptDir "runelite"

$runAll = -not ($UpdateRepos -or $MergeRuneliteUpstream -or ($InstallDep.Count -gt 0))

# ---------------------------------------------------------------------------
# -Update: fetch and update submodules
# ---------------------------------------------------------------------------
if ($Update) {
    Write-Info "Updating submodules..."
    Push-Location $ScriptDir
    try {
        git fetch --all --tags --prune 2>&1 | Out-Null
        git submodule update --init --recursive --remote
        if ($LASTEXITCODE -ne 0) { Write-Err "Submodule update failed."; exit 1 }
        $ErrorActionPreference = "SilentlyContinue"
        if (Test-Path $botPath) { Push-Location $botPath; git checkout main 2>$null | Out-Null; Pop-Location }
        if (Test-Path $runelitePath) { Push-Location $runelitePath; git checkout master 2>$null | Out-Null; Pop-Location }
        $ErrorActionPreference = "Stop"
        Write-Success "Update complete."
    } finally { Pop-Location }
    exit 0
}

# ---------------------------------------------------------------------------
# UpdateRepos
# ---------------------------------------------------------------------------
if ($runAll -or $UpdateRepos) {
    Write-Info "Updating repos..."
    Push-Location $ScriptDir
    try {
        git fetch --all --tags --prune 2>&1 | Out-Null
        git submodule update --init --recursive --remote
        if ($LASTEXITCODE -ne 0) { Write-Err "Submodule update failed."; exit 1 }
        git checkout main 2>$null | Out-Null
        git pull 2>$null | Out-Null
        $ErrorActionPreference = "SilentlyContinue"
        if (Test-Path $botPath) {
            Push-Location $botPath
            git checkout main 2>$null | Out-Null
            git pull 2>$null | Out-Null
            Pop-Location
        }
        if (Test-Path $runelitePath) {
            Push-Location $runelitePath
            git remote get-url upstream 2>$null | Out-Null
            if ($LASTEXITCODE -ne 0) { git remote add upstream https://github.com/runelite/runelite.git 2>$null | Out-Null }
            git checkout master 2>$null | Out-Null
            git pull 2>$null | Out-Null
            Pop-Location
        }
        $ErrorActionPreference = "Stop"
        Write-Success "Repos updated."
    } finally { Pop-Location }
}

# ---------------------------------------------------------------------------
# MergeRuneliteUpstream
# ---------------------------------------------------------------------------
if ($runAll -or $MergeRuneliteUpstream) {
    Write-Info "Merging runelite upstream..."
    if (-not (Test-Path $runelitePath)) {
        Write-Err "runelite directory not found."
        exit 1
    }
    Push-Location $runelitePath
    try {
        # Cleanup: remove Java HotSpot error logs
        $errorLogs = Get-ChildItem -Path $runelitePath -Filter "hs_err_pid*.log" -Recurse -ErrorAction SilentlyContinue
        foreach ($log in $errorLogs) {
            Remove-Item $log.FullName -Force -ErrorAction SilentlyContinue
        }
        # Fetch
        $remote = "upstream"
        git remote get-url upstream 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { $remote = "origin" }
        git fetch $remote --tags --prune 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Err "Fetch failed."; exit 1 }
        # Get latest release tag (sorted newest first)
        $tags = git tag --list "runelite-parent-*" --sort=-version:refname 2>$null
        if (-not $tags) { Write-Err "No release tags found."; exit 1 }
        $latestTag = ($tags -split "`n" | Where-Object { $_.Trim() } | Select-Object -First 1).Trim()
        $latestCommit = (git rev-parse $latestTag 2>$null).Trim()
        if (-not $latestCommit) { Write-Err "Could not resolve tag $latestTag"; exit 1 }
        $currentHead = (git rev-parse HEAD 2>$null).Trim()
        # Check if current HEAD is at or ahead of latest release
        git merge-base --is-ancestor $latestCommit $currentHead 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Already at or ahead of $latestTag."
        } else {
            # Check uncommitted changes
            $status = git status --porcelain 2>$null
            if ($status) {
                Write-Err "Uncommitted changes. Commit or stash before merging."
                exit 1
            }
            # Merge
            git merge --no-edit --no-ff $latestCommit 2>&1 | Out-String
            if ($LASTEXITCODE -ne 0) {
                git merge --abort 2>$null | Out-Null
                Write-Err "Merge failed."
                exit 1
            }
            Write-Success "Merged $latestTag."
        }
    } finally { Pop-Location }
}

# ---------------------------------------------------------------------------
# InstallDep
# ---------------------------------------------------------------------------
$depsToInstall = @()
if ($runAll) {
    $depsToInstall = @("PySide6", "psutil", "requests", "pyautogui", "Pillow", "numpy", "scipy")
} elseif ($InstallDep.Count -gt 0) {
    $depsToInstall = @()
    foreach ($item in $InstallDep) {
        $depsToInstall += $item -split ","
    }
    $depsToInstall = $depsToInstall | ForEach-Object { $_.Trim() } | Where-Object { $_ }
}

if ($depsToInstall.Count -gt 0) {
    $pyExe = $null
    try { $pyExe = (Get-Command python -ErrorAction Stop).Source } catch {}
    if (-not $pyExe) { try { $pyExe = (Get-Command py -ErrorAction Stop).Source } catch {} }
    if (-not $pyExe) {
        Write-Err "Python not found. Run setup with -InstallPython first."
        exit 1
    }
    $env:PIP_DISABLE_PIP_VERSION_CHECK = "1"
    foreach ($dep in $depsToInstall) {
        Write-Info "Installing $dep..."
        & $pyExe -m pip install $dep --quiet --disable-pip-version-check
        if ($LASTEXITCODE -ne 0) { Write-Err "$dep installation failed."; exit 1 }
        Write-Success "$dep installed."
    }
}

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
if ($runAll -or $UpdateRepos -or $MergeRuneliteUpstream -or ($depsToInstall.Count -gt 0)) {
    Write-Success "Setup complete."
}
