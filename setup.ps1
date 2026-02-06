<#
.SYNOPSIS
    One-time setup for flez-bot (umbrella repo with bot_runelite_IL + runelite submodules).

.DESCRIPTION
    Ensures prerequisites (Git, Python 3, Chocolatey) are installed, initializes submodules,
    checks out correct branches, and installs PySide6. Java is provided by Gradle toolchains.
    Use -Update to fetch and update submodules to latest main/master (for launcher to call).

.EXAMPLE
    .\setup.ps1
    .\setup.ps1 -SkipPrereqs
    .\setup.ps1 -Update
#>

param(
    [switch]$SkipPrereqs,
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

# ---------------------------------------------------------------------------
# -Update: fetch and update submodules to latest main/master only
# ---------------------------------------------------------------------------
if ($Update) {
    Write-Info "=============================================="
    Write-Info "  flez-bot - Update (fetch + submodule update)"
    Write-Info "=============================================="
    Write-Host ""
    Push-Location $ScriptDir
    try {
        if (-not (Test-Path (Join-Path $ScriptDir ".git"))) {
            Write-Err "Not a git repository. Run full setup first."
            exit 1
        }
        Write-Info "Fetching from remotes..."
        git fetch --all --tags --prune 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Warn "git fetch had issues (non-fatal)." }
        Write-Info "Updating submodules to latest (main / master)..."
        git submodule update --init --recursive --remote
        if ($LASTEXITCODE -ne 0) {
            Write-Err "Submodule update failed."
            exit 1
        }
        $prevErr = $ErrorActionPreference
        $ErrorActionPreference = "SilentlyContinue"
        if (Test-Path $botPath) {
            Push-Location $botPath
            git checkout main 2>$null | Out-Null
            Pop-Location
        }
        if (Test-Path $runelitePath) {
            Push-Location $runelitePath
            git checkout master 2>$null | Out-Null
            Pop-Location
        }
        $ErrorActionPreference = $prevErr
        Write-Success "Update complete."
    } finally {
        Pop-Location
    }
    exit 0
}

# ---------------------------------------------------------------------------
# Full setup
# ---------------------------------------------------------------------------
Write-Info "=============================================="
Write-Info "  flez-bot - Setup"
Write-Info "=============================================="
Write-Host ""

# ---------------------------------------------------------------------------
# 1. Prerequisites
# ---------------------------------------------------------------------------
if (-not $SkipPrereqs) {
    Write-Info "[1/6] Checking prerequisites..."

    # Git (required)
    $gitExe = Get-Command git -ErrorAction SilentlyContinue
    if (-not $gitExe) {
        Write-Warn "Git not found."
        $choco = Get-Command choco -ErrorAction SilentlyContinue
        if ($choco) {
            Write-Info "Installing Git via Chocolatey..."
            choco install git -y
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
            $gitExe = Get-Command git -ErrorAction SilentlyContinue
        }
        if (-not $gitExe) {
            Write-Err "Git is required. Install from https://git-scm.com/ or run: choco install git -y"
            exit 1
        }
    }
    Write-Success "  Git: $($gitExe.Source)"

    # PowerShell 5.1+
    $psVer = $PSVersionTable.PSVersion
    if ($psVer.Major -lt 5) {
        Write-Err "PowerShell 5.1 or later is required. Current: $($psVer)"
        exit 1
    }
    Write-Success "  PowerShell: $($psVer)"

    # Chocolatey (optional but recommended for installing Git/Python)
    $choco = Get-Command choco -ErrorAction SilentlyContinue
    if (-not $choco) {
        Write-Warn "  Chocolatey not found. Some dependencies may need manual install."
        Write-Info "  To install: https://chocolatey.org/install (run as Administrator)"
    } else {
        Write-Success "  Chocolatey: installed"
    }

    # Python 3 (required for bot GUI)
    $py = $null
    try {
        $py = Get-Command python -ErrorAction Stop
    } catch {}
    if (-not $py) {
        try { $py = Get-Command py -ErrorAction Stop } catch {}
    }
    if (-not $py) {
        Write-Warn "Python 3 not found."
        if ($choco) {
            Write-Info "Installing Python 3 via Chocolatey..."
            choco install python -y
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
            $py = Get-Command python -ErrorAction SilentlyContinue
        }
        if (-not $py) {
            Write-Err "Python 3 is required for the bot GUI. Install from https://www.python.org/ or run: choco install python -y"
            exit 1
        }
    }
    $pyVer = & $py.Source --version 2>&1 | Out-String
    Write-Success "  Python: $($pyVer.Trim())"

    Write-Host ""
} else {
    Write-Info "[1/6] Skipping prerequisite checks (SkipPrereqs)."
    Write-Host ""
}

# ---------------------------------------------------------------------------
# 2. Initialize submodules
# ---------------------------------------------------------------------------
Write-Info "[2/6] Initializing submodules..."
Push-Location $ScriptDir
try {
    $submoduleStatus = git submodule status 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Err "Not a git repository or submodules not configured. Ensure you cloned the umbrella repo."
        exit 1
    }
    git submodule update --init --recursive
    if ($LASTEXITCODE -ne 0) {
        Write-Err "Submodule update failed."
        exit 1
    }
    Write-Success "  Submodules initialized."
} finally {
    Pop-Location
}
Write-Host ""

# ---------------------------------------------------------------------------
# 3. Checkout correct branches
# ---------------------------------------------------------------------------
Write-Info "[3/6] Checking out branches..."

# Git writes "Already on 'main'" to stderr; avoid that triggering Stop
$prevErrorAction = $ErrorActionPreference
$ErrorActionPreference = "SilentlyContinue"

if (Test-Path $botPath) {
    Push-Location $botPath
    try {
        git checkout main 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { git checkout -b main origin/main 2>$null | Out-Null }
        Write-Success "  bot_runelite_IL: main"
    } finally { Pop-Location }
} else {
    Write-Warn "  bot_runelite_IL directory not found (submodule may not be added yet)."
}

if (Test-Path $runelitePath) {
    Push-Location $runelitePath
    try {
        git checkout master 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { git checkout -b master origin/master 2>$null | Out-Null }
        # Ensure upstream remote exists for release checks
        git remote get-url upstream 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            git remote add upstream https://github.com/runelite/runelite.git 2>$null | Out-Null
            Write-Success "  runelite: master (upstream remote added)"
        } else {
            Write-Success "  runelite: master"
        }
    } finally { Pop-Location }
} else {
    Write-Warn "  runelite directory not found (submodule may not be added yet)."
}

$ErrorActionPreference = $prevErrorAction
Write-Host ""

# ---------------------------------------------------------------------------
# 4. Verify structure
# ---------------------------------------------------------------------------
Write-Info "[4/6] Verifying structure..."

$ok = $true
if (-not (Test-Path (Join-Path $botPath "gui\launcher_pyside.py"))) {
    Write-Err "  bot_runelite_IL/gui/launcher_pyside.py not found."
    $ok = $false
}
if (Test-Path $runelitePath) {
    if (-not (Test-Path (Join-Path $runelitePath "gradlew") -PathType Leaf) -and -not (Test-Path (Join-Path $runelitePath "gradlew.bat") -PathType Leaf)) {
        Write-Err "  runelite/gradlew or gradlew.bat not found."
        $ok = $false
    }
}
if (-not $ok) {
    Write-Err "Structure verification failed. Ensure submodules are initialized."
    exit 1
}
Write-Success "  Directory structure OK."
Write-Host ""

# ---------------------------------------------------------------------------
# 5. Install Python GUI dependency (PySide6)
# ---------------------------------------------------------------------------
Write-Info "[5/6] Installing PySide6 (Python GUI)..."
$pyExe = $null
try { $pyExe = (Get-Command python -ErrorAction Stop).Source } catch {}
if (-not $pyExe) {
    try { $pyExe = (Get-Command py -ErrorAction Stop).Source } catch {}
}
if ($pyExe) {
    & $pyExe -m pip install PySide6 --quiet
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "  pip install PySide6 failed. Try manually: python -m pip install PySide6"
    } else {
        Write-Success "  PySide6 installed."
    }
} else {
    Write-Warn "  Python not found; skipping PySide6 install. Install Python and run: pip install PySide6"
}
Write-Host ""

# ---------------------------------------------------------------------------
# 6. Success and next steps
# ---------------------------------------------------------------------------
Write-Info "[6/6] Done."
Write-Host ""
Write-Success "=============================================="
Write-Success "  Setup complete"
Write-Success "=============================================="
Write-Host ""
Write-Info "Next steps:"
Write-Info "  1. Add credentials to bot_runelite_IL/credentials/ (e.g. myaccount.properties)"
Write-Info "  2. Run the launcher from the flez-bot directory:"
Write-Info "       python launcher.py"
Write-Info "  (Or from anywhere: python path\to\flez-bot\launcher.py)"
Write-Host ""
Write-Info "To update repos to latest main/master:"
Write-Info "  .\setup.ps1 -Update"
Write-Host ""
