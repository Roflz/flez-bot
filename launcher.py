#!/usr/bin/env python3
"""
flez-bot launcher (run this instead of bot_runelite_IL/gui_pyside.py).

Runs from the flez-bot root. Updates repos (setup.ps1 -Update), does a quick
readiness check, then launches the PySide6 GUI. Intended for normal use and for
packaging as flez-bot.exe (installer will run setup; launcher runs this flow).
"""

import os
import sys
import subprocess
from pathlib import Path

def _flez_bot_root():
    """Install root: directory containing the exe when frozen, else launcher.py's directory."""
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parent

def _run_setup_update():
    """Run setup.ps1 -Update to fetch and update submodules to latest main/master."""
    root = _flez_bot_root()
    setup_ps1 = root / "setup.ps1"
    if not setup_ps1.is_file():
        return False
    if sys.platform != "win32":
        return False
    try:
        subprocess.run(
            ["powershell", "-ExecutionPolicy", "Bypass", "-File", str(setup_ps1), "-Update"],
            cwd=str(root),
            timeout=300,
            capture_output=True,
        )
        return True
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return False

def _run_setup_full():
    """Run full setup.ps1 (no -Update). Returns True if exit code was 0."""
    root = _flez_bot_root()
    setup_ps1 = root / "setup.ps1"
    if not setup_ps1.is_file():
        return False
    if sys.platform != "win32":
        return False
    try:
        r = subprocess.run(
            ["powershell", "-ExecutionPolicy", "Bypass", "-File", str(setup_ps1)],
            cwd=str(root),
            timeout=600,
        )
        return r.returncode == 0
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return False

def _readiness_check():
    """
    Check runelite path, gradlew, and PySide6. Returns (ok: bool, missing: list[str]).
    """
    root = _flez_bot_root()
    bot_path = root / "bot_runelite_IL"
    runelite_path = root / "runelite"
    missing = []

    if not runelite_path.is_dir():
        missing.append("runelite directory not found")
    else:
        gradlew = runelite_path / "gradlew.bat" if sys.platform == "win32" else runelite_path / "gradlew"
        if not gradlew.is_file():
            missing.append("runelite/gradlew (or gradlew.bat) not found")

    if not (bot_path / "gui_pyside.py").exists():
        missing.append("bot_runelite_IL/gui_pyside.py not found")

    try:
        import PySide6  # noqa: F401
    except ImportError:
        missing.append("PySide6 not installed (run: pip install PySide6)")

    return len(missing) == 0, missing


def _pause_if_frozen():
    """If running as exe, pause so the user can read the console error."""
    if getattr(sys, "frozen", False):
        input("Press Enter to close...")


def main():
    root = _flez_bot_root()
    bot_path = root / "bot_runelite_IL"

    # Ensure process working directory is the install root (fixes Start Menu / shortcut launch)
    try:
        os.chdir(str(root))
    except OSError:
        pass

    # 1. Update repos (setup.ps1 -Update); non-blocking if it fails
    print("Checking for updates...")
    if not _run_setup_update():
        print("Update check skipped or failed (e.g. no Git or network). Continuing.")

    # 2. Readiness check
    ok, missing = _readiness_check()
    if not ok:
        print("Setup incomplete:", ", ".join(missing))
        print("Running full setup (this may take a few minutes)...")
        if not _run_setup_full():
            print("Setup failed. Run from the flez-bot directory: .\\setup.ps1")
            _pause_if_frozen()
            sys.exit(1)
        ok, missing = _readiness_check()
        if not ok:
            print("Still missing:", ", ".join(missing))
            _pause_if_frozen()
            sys.exit(1)

    # 3. Launch GUI (add bot_runelite_IL to path and run its entry point)
    sys.path.insert(0, str(bot_path))
    import gui_pyside
    gui_pyside.main()


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print("Error:", e)
        _pause_if_frozen()
        raise
