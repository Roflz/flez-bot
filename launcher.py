#!/usr/bin/env python3
"""
flez-bot launcher. Runs prereq check, calls setup for missing items, then launches GUI.
Use -dev to skip git repo checks.
"""

import argparse
import os
import subprocess
import sys
from pathlib import Path


def _flez_bot_root():
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parent


def _run_setup(args_list):
    """Run setup.ps1 with given args. Returns True if exit code 0."""
    root = _flez_bot_root()
    setup_ps1 = root / "setup.ps1"
    if not setup_ps1.is_file():
        return False
    if sys.platform != "win32":
        return False
    cmd = ["powershell", "-ExecutionPolicy", "Bypass", "-File", str(setup_ps1)] + args_list
    try:
        r = subprocess.run(cmd, cwd=str(root), timeout=600)
        return r.returncode == 0
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return False


def _run_setup_update():
    root = _flez_bot_root()
    setup_ps1 = root / "setup.ps1"
    if not setup_ps1.is_file() or sys.platform != "win32":
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


def _git_installed():
    try:
        subprocess.run(["git", "--version"], capture_output=True, timeout=5)
        return True
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return False


def _python_installed():
    try:
        subprocess.run([sys.executable, "--version"], capture_output=True, timeout=5)
        return True
    except Exception:
        return False


def _repo_on_branch_latest_clean(root, branch):
    """Check repo at root is on branch, at latest, no uncommitted changes."""
    try:
        r = subprocess.run(
            ["git", "rev-parse", "--abbrev-ref", "HEAD"],
            cwd=str(root),
            capture_output=True,
            text=True,
            timeout=10,
        )
        if r.returncode != 0 or r.stdout.strip() != branch:
            return False, "not on " + branch
        r = subprocess.run(
            ["git", "status", "--porcelain"],
            cwd=str(root),
            capture_output=True,
            text=True,
            timeout=10,
        )
        if r.returncode != 0 or r.stdout.strip():
            return False, "uncommitted changes"
        r = subprocess.run(
            ["git", "fetch", "origin", "--tags", "--prune"],
            cwd=str(root),
            capture_output=True,
            timeout=60,
        )
        r = subprocess.run(
            ["git", "rev-list", "HEAD..origin/" + branch, "--count"],
            cwd=str(root),
            capture_output=True,
            text=True,
            timeout=10,
        )
        if r.returncode == 0 and r.stdout.strip() and int(r.stdout.strip()) > 0:
            return False, "behind origin/" + branch
        return True, None
    except Exception as e:
        return False, str(e)


def _runelite_behind_upstream(runelite_path):
    """Check if runelite HEAD is behind latest runelite-parent-* release."""
    try:
        r = subprocess.run(
            ["git", "fetch", "upstream", "--tags", "--prune"],
            cwd=str(runelite_path),
            capture_output=True,
            timeout=60,
        )
        if r.returncode != 0:
            r = subprocess.run(
                ["git", "fetch", "origin", "--tags", "--prune"],
                cwd=str(runelite_path),
                capture_output=True,
                timeout=60,
            )
        r = subprocess.run(
            ["git", "tag", "--list", "runelite-parent-*", "--sort=-version:refname"],
            cwd=str(runelite_path),
            capture_output=True,
            text=True,
            timeout=10,
        )
        if r.returncode != 0 or not r.stdout.strip():
            return False, None
        latest_tag = r.stdout.strip().split("\n")[0].strip()
        r = subprocess.run(
            ["git", "rev-parse", latest_tag],
            cwd=str(runelite_path),
            capture_output=True,
            text=True,
            timeout=10,
        )
        if r.returncode != 0:
            return False, None
        latest_commit = r.stdout.strip()
        r = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=str(runelite_path),
            capture_output=True,
            text=True,
            timeout=10,
        )
        if r.returncode != 0:
            return False, None
        current_head = r.stdout.strip()
        r = subprocess.run(
            ["git", "merge-base", "--is-ancestor", latest_commit, current_head],
            cwd=str(runelite_path),
            capture_output=True,
            timeout=10,
        )
        return r.returncode != 0, latest_tag
    except Exception:
        return False, None


def _prereq_check(dev_mode):
    """
    Returns (ok, missing, setup_args).
    setup_args: list of args to pass to setup.ps1 e.g. ["-InstallGit", "-InstallDep", "psutil"]
    """
    root = _flez_bot_root()
    bot_path = root / "bot_runelite_IL"
    runelite_path = root / "runelite"
    missing = []
    setup_args = []

    # Git
    if not _git_installed():
        missing.append("Git not installed")
        return False, missing, []  # Don't call setup - warn and exit

    # Python
    if not _python_installed():
        missing.append("Python not installed")
        return False, missing, []  # Don't call setup - warn and exit

    # Git repo checks (skipped in dev mode)
    if not dev_mode and _git_installed():
        needs_update = False
        # Submodules not initialized
        if not (bot_path / ".git").exists() or not (runelite_path / ".git").exists():
            missing.append("Submodules not initialized")
            needs_update = True
        # Umbrella
        elif (root / ".git").exists():
            ok, err = _repo_on_branch_latest_clean(root, "main")
            if not ok:
                missing.append(f"Umbrella repo: {err}")
                needs_update = True
        else:
            missing.append("Not a git repository")
            needs_update = True

        if needs_update:
            setup_args.extend(["-UpdateRepos"])

        # Submodule branch/state (only if inited)
        if (bot_path / ".git").exists():
            ok, err = _repo_on_branch_latest_clean(bot_path, "main")
            if not ok:
                missing.append(f"bot_runelite_IL: {err}")
                if "-UpdateRepos" not in setup_args:
                    setup_args.extend(["-UpdateRepos"])

        if (runelite_path / ".git").exists():
            ok, err = _repo_on_branch_latest_clean(runelite_path, "master")
            if not ok:
                missing.append(f"runelite: {err}")
                if "-UpdateRepos" not in setup_args:
                    setup_args.extend(["-UpdateRepos"])

            # Runelite upstream
            behind, tag = _runelite_behind_upstream(runelite_path)
            if behind and tag:
                missing.append(f"runelite behind upstream release {tag}")
                setup_args.extend(["-MergeRuneliteUpstream"])

    # Dependencies (individual)
    missing_deps = []
    _DEP_MODULES = ("PySide6", "psutil", "requests", "pyautogui", "PIL", "numpy", "scipy")
    _PIP_NAMES = {"PIL": "Pillow"}  # import name -> pip package name
    for mod in _DEP_MODULES:
        try:
            __import__(mod)
        except ImportError:
            pip_name = _PIP_NAMES.get(mod, mod)
            missing.append(f"{mod} not installed")
            missing_deps.append(pip_name)
    if missing_deps:
        setup_args.extend(["-InstallDep", ",".join(missing_deps)])

    # Dedupe: -UpdateRepos and -MergeRuneliteUpstream once
    seen = set()
    deduped = []
    for arg in setup_args:
        if arg not in seen:
            seen.add(arg)
            deduped.append(arg)

    return len(missing) == 0, missing, deduped


def _pause_if_frozen(message=None):
    if not getattr(sys, "frozen", False):
        return
    text = message or "An error occurred."
    try:
        if sys.stdin is None or getattr(sys.stdin, "closed", True):
            raise RuntimeError("no stdin")
        input("Press Enter to close...")
    except (RuntimeError, OSError):
        if sys.platform == "win32":
            try:
                import ctypes
                ctypes.windll.user32.MessageBoxW(0, text, "flez-bot", 0x10)
            except Exception:
                pass


def main():
    parser = argparse.ArgumentParser(description="flez-bot launcher")
    parser.add_argument("-dev", action="store_true", help="Skip git repo checks")
    args = parser.parse_args()

    root = _flez_bot_root()
    bot_path = root / "bot_runelite_IL"

    try:
        from dotenv import load_dotenv
        load_dotenv(root / ".env")
    except ImportError:
        pass

    try:
        os.chdir(str(root))
    except OSError:
        pass

    # Update (non-blocking)
    if not args.dev:
        print("Checking for updates...")
        if not _run_setup_update():
            print("Update check skipped or failed. Continuing.")

    # Prereq check
    ok, missing, setup_args = _prereq_check(dev_mode=args.dev)
    if not ok:
        print("Setup incomplete:", ", ".join(missing))
        if not setup_args:
            # Git or Python missing - can't run setup
            msg = "Re-install flez-bot or install the missing component(s) separately."
            print(msg)
            _pause_if_frozen(msg)
            sys.exit(1)
        print("Running setup...")
        if not _run_setup(setup_args):
            msg = "Setup failed."
            print(msg)
            _pause_if_frozen(msg)
            sys.exit(1)
        ok, missing, _ = _prereq_check(dev_mode=args.dev)
        if not ok:
            msg = "Still missing: " + ", ".join(missing)
            print(msg)
            _pause_if_frozen(msg)
            sys.exit(1)

    # Launch GUI
    sys.path.insert(0, str(bot_path))
    import gui_pyside
    gui_pyside.main()


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        err_msg = str(e)
        print("Error:", err_msg)
        _pause_if_frozen("Error: " + err_msg)
        raise
