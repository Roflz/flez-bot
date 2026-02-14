#!/usr/bin/env python3
"""
flez-bot launcher. Runs prereq check, calls setup for missing items, then launches GUI.
Use -dev to skip git repo checks.
"""

import argparse
import logging
import os
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path


def _flez_bot_root():
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parent


def _setup_launcher_logger(root):
    logs_dir = root / "bot_runelite_IL" / "logs"
    if not logs_dir.exists():
        logs_dir = root / "logs"
    logs_dir.mkdir(parents=True, exist_ok=True)
    log_path = logs_dir / f"launcher_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log"
    logger = logging.getLogger("flez_launcher")
    logger.setLevel(logging.INFO)
    logger.handlers.clear()
    handler = logging.FileHandler(log_path, encoding="utf-8")
    handler.setFormatter(logging.Formatter("[%(asctime)s] %(levelname)s: %(message)s", "%H:%M:%S"))
    logger.addHandler(handler)
    return logger, log_path


class _StartupSplash:
    def __init__(self, enabled=True):
        self.enabled = enabled and sys.platform == "win32"
        self._tk = None
        self._root = None
        self._label = None
        if not self.enabled:
            return
        try:
            import tkinter as tk
            self._tk = tk
            self._root = tk.Tk()
            self._root.title("flez-bot")
            self._root.geometry("520x120")
            self._root.resizable(False, False)
            self._root.attributes("-topmost", True)
            self._root.configure(bg="#1e1e1e")
            frame = tk.Frame(self._root, bg="#1e1e1e")
            frame.pack(expand=True, fill="both", padx=20, pady=20)
            title = tk.Label(frame, text="Starting flez-bot...", fg="#ffffff", bg="#1e1e1e", font=("Segoe UI", 12, "bold"))
            title.pack(anchor="w")
            self._label = tk.Label(frame, text="Initializing...", fg="#d0d0d0", bg="#1e1e1e", font=("Segoe UI", 10))
            self._label.pack(anchor="w", pady=(8, 0))
            self._root.update_idletasks()
            self._root.update()
        except Exception:
            self.enabled = False
            self._root = None
            self._label = None

    def update(self, message):
        if not self.enabled or not self._root or not self._label:
            return
        try:
            self._label.config(text=message)
            self._root.update_idletasks()
            self._root.update()
        except Exception:
            pass

    def close(self):
        if not self.enabled or not self._root:
            return
        try:
            self._root.destroy()
        except Exception:
            pass


def _prepend_dir_to_path(env, directory):
    if not directory:
        return env
    directory = str(directory)
    current = env.get("PATH", "")
    parts = [p.strip() for p in current.split(os.pathsep) if p.strip()]
    if directory not in parts:
        env["PATH"] = directory + os.pathsep + current
    return env


def _find_git_exe():
    path_git = shutil.which("git")
    if path_git:
        return path_git
    candidates = [
        Path(os.environ.get("LOCALAPPDATA", "")) / "Programs" / "Git" / "cmd" / "git.exe",
        Path(os.environ.get("ProgramFiles", "")) / "Git" / "cmd" / "git.exe",
        Path(os.environ.get("ProgramFiles(x86)", "")) / "Git" / "cmd" / "git.exe",
    ]
    for candidate in candidates:
        if candidate.is_file():
            return str(candidate)
    return None


def _find_python_exe():
    path_python = shutil.which("python")
    if path_python:
        return path_python
    candidates = [
        Path(os.environ.get("LOCALAPPDATA", "")) / "Programs" / "Python" / "Python313" / "python.exe",
        Path(os.environ.get("ProgramFiles", "")) / "Python313" / "python.exe",
        Path(os.environ.get("ProgramFiles(x86)", "")) / "Python313" / "python.exe",
    ]
    for candidate in candidates:
        if candidate.is_file():
            return str(candidate)
    return None


def _run_setup(args_list, logger=None):
    """Run setup.ps1 with given args. Returns True if exit code 0."""
    root = _flez_bot_root()
    setup_ps1 = root / "setup.ps1"
    if not setup_ps1.is_file():
        if logger:
            logger.error("setup.ps1 not found at %s", setup_ps1)
        return False
    if sys.platform != "win32":
        if logger:
            logger.error("Non-Windows platform does not support setup.ps1 execution")
        return False
    cmd = ["powershell", "-ExecutionPolicy", "Bypass", "-File", str(setup_ps1)] + args_list
    try:
        r = subprocess.run(cmd, cwd=str(root), timeout=600, capture_output=True, text=True)
        if logger:
            logger.info("setup command: %s", " ".join(cmd))
            if r.stdout:
                logger.info("setup stdout:\n%s", r.stdout.strip())
            if r.stderr:
                logger.warning("setup stderr:\n%s", r.stderr.strip())
            logger.info("setup exit code: %s", r.returncode)
        return r.returncode == 0
    except (subprocess.TimeoutExpired, FileNotFoundError) as e:
        if logger:
            logger.exception("setup invocation failed: %s", e)
        return False


def _summarize_subprocess_output(stdout_text, stderr_text, max_len=180):
    combined = []
    if stdout_text and stdout_text.strip():
        combined.append(stdout_text.strip())
    if stderr_text and stderr_text.strip():
        combined.append(stderr_text.strip())
    if not combined:
        return ""
    text = " | ".join(combined).replace("\r", " ").replace("\n", " ")
    if len(text) > max_len:
        text = text[: max_len - 3] + "..."
    return text


def _run_setup_update(logger=None):
    root = _flez_bot_root()
    setup_ps1 = root / "setup.ps1"
    if not setup_ps1.is_file():
        return False, "setup.ps1 not found"
    if sys.platform != "win32":
        return False, "non-Windows platform"
    try:
        r = subprocess.run(
            ["powershell", "-ExecutionPolicy", "Bypass", "-File", str(setup_ps1), "-Update"],
            cwd=str(root),
            timeout=300,
            capture_output=True,
            text=True,
        )
        if logger:
            if r.stdout:
                logger.info("update stdout:\n%s", r.stdout.strip())
            if r.stderr:
                logger.warning("update stderr:\n%s", r.stderr.strip())
            logger.info("update exit code: %s", r.returncode)
        if r.returncode == 0:
            return True, ""
        summary = _summarize_subprocess_output(r.stdout, r.stderr)
        detail = f"setup.ps1 -Update exited with code {r.returncode}"
        if summary:
            detail += f" ({summary})"
        return False, detail
    except (subprocess.TimeoutExpired, FileNotFoundError) as e:
        if logger:
            logger.exception("update invocation failed: %s", e)
        return False, str(e)


def _git_installed():
    git_exe = _find_git_exe()
    if not git_exe:
        return False
    env = os.environ.copy()
    _prepend_dir_to_path(env, Path(git_exe).parent)
    try:
        subprocess.run([git_exe, "--version"], capture_output=True, timeout=5, env=env)
        return True
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return False


def _python_installed():
    python_exe = _find_python_exe()
    if not python_exe:
        return False
    try:
        subprocess.run([python_exe, "--version"], capture_output=True, timeout=5)
        return True
    except Exception:
        return False


def _repo_on_branch_latest_clean(root, branch, git_exe):
    """Check repo at root is on branch, at latest, no uncommitted changes."""
    env = os.environ.copy()
    _prepend_dir_to_path(env, Path(git_exe).parent)
    try:
        r = subprocess.run(
            [git_exe, "rev-parse", "--abbrev-ref", "HEAD"],
            cwd=str(root),
            capture_output=True,
            text=True,
            timeout=10,
            env=env,
        )
        if r.returncode != 0 or r.stdout.strip() != branch:
            return False, "not on " + branch
        r = subprocess.run(
            [git_exe, "status", "--porcelain"],
            cwd=str(root),
            capture_output=True,
            text=True,
            timeout=10,
            env=env,
        )
        if r.returncode != 0 or r.stdout.strip():
            return False, "uncommitted changes"
        r = subprocess.run(
            [git_exe, "fetch", "origin", "--tags", "--prune"],
            cwd=str(root),
            capture_output=True,
            timeout=60,
            env=env,
        )
        r = subprocess.run(
            [git_exe, "rev-list", "HEAD..origin/" + branch, "--count"],
            cwd=str(root),
            capture_output=True,
            text=True,
            timeout=10,
            env=env,
        )
        if r.returncode == 0 and r.stdout.strip() and int(r.stdout.strip()) > 0:
            return False, "behind origin/" + branch
        return True, None
    except Exception as e:
        return False, str(e)


def _runelite_behind_upstream(runelite_path, git_exe):
    """Check if runelite HEAD is behind latest runelite-parent-* release."""
    env = os.environ.copy()
    _prepend_dir_to_path(env, Path(git_exe).parent)
    try:
        r = subprocess.run(
            [git_exe, "fetch", "upstream", "--tags", "--prune"],
            cwd=str(runelite_path),
            capture_output=True,
            timeout=60,
            env=env,
        )
        if r.returncode != 0:
            r = subprocess.run(
                [git_exe, "fetch", "origin", "--tags", "--prune"],
                cwd=str(runelite_path),
                capture_output=True,
                timeout=60,
                env=env,
            )
        r = subprocess.run(
            [git_exe, "tag", "--list", "runelite-parent-*", "--sort=-version:refname"],
            cwd=str(runelite_path),
            capture_output=True,
            text=True,
            timeout=10,
            env=env,
        )
        if r.returncode != 0 or not r.stdout.strip():
            return False, None
        latest_tag = r.stdout.strip().split("\n")[0].strip()
        r = subprocess.run(
            [git_exe, "rev-parse", latest_tag],
            cwd=str(runelite_path),
            capture_output=True,
            text=True,
            timeout=10,
            env=env,
        )
        if r.returncode != 0:
            return False, None
        latest_commit = r.stdout.strip()
        r = subprocess.run(
            [git_exe, "rev-parse", "HEAD"],
            cwd=str(runelite_path),
            capture_output=True,
            text=True,
            timeout=10,
            env=env,
        )
        if r.returncode != 0:
            return False, None
        current_head = r.stdout.strip()
        r = subprocess.run(
            [git_exe, "merge-base", "--is-ancestor", latest_commit, current_head],
            cwd=str(runelite_path),
            capture_output=True,
            timeout=10,
            env=env,
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
    git_exe = _find_git_exe()

    # Git
    if not git_exe or not _git_installed():
        missing.append("Git not installed")
        return False, missing, []  # Don't call setup - warn and exit

    # Python
    if not _python_installed():
        missing.append("Python not installed")
        return False, missing, []  # Don't call setup - warn and exit

    # Git repo checks (skipped in dev mode)
    if not dev_mode and git_exe:
        needs_update = False
        # Submodules not initialized
        if not (bot_path / ".git").exists() or not (runelite_path / ".git").exists():
            missing.append("Submodules not initialized")
            needs_update = True
        # Umbrella
        elif (root / ".git").exists():
            ok, err = _repo_on_branch_latest_clean(root, "main", git_exe)
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
            ok, err = _repo_on_branch_latest_clean(bot_path, "main", git_exe)
            if not ok:
                missing.append(f"bot_runelite_IL: {err}")
                if "-UpdateRepos" not in setup_args:
                    setup_args.extend(["-UpdateRepos"])

        if (runelite_path / ".git").exists():
            ok, err = _repo_on_branch_latest_clean(runelite_path, "master", git_exe)
            if not ok:
                missing.append(f"runelite: {err}")
                if "-UpdateRepos" not in setup_args:
                    setup_args.extend(["-UpdateRepos"])

            # Runelite upstream
            behind, tag = _runelite_behind_upstream(runelite_path, git_exe)
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
    logger, log_path = _setup_launcher_logger(root)
    splash = _StartupSplash(enabled=getattr(sys, "frozen", False))

    try:
        from dotenv import load_dotenv
        load_dotenv(root / ".env")
    except ImportError:
        pass

    try:
        os.chdir(str(root))
    except OSError:
        pass

    def _status(message):
        print(message)
        logger.info(message)
        splash.update(message)

    # Update (non-blocking)
    if not args.dev:
        _status("Checking for updates...")
        update_ok, update_detail = _run_setup_update(logger=logger)
        if not update_ok:
            if update_detail:
                _status("Update check issue: " + update_detail + ". Continuing.")
            else:
                _status("Update check failed. Continuing.")

    # Prereq check
    _status("Checking prerequisites...")
    ok, missing, setup_args = _prereq_check(dev_mode=args.dev)
    if not ok:
        _status("Setup incomplete: " + ", ".join(missing))
        if not setup_args:
            # Git or Python missing - can't run setup
            msg = "Re-install flez-bot or install the missing component(s) separately."
            _status(msg)
            _status("Launcher log: " + str(log_path))
            splash.close()
            _pause_if_frozen(msg)
            sys.exit(1)
        _status("Running setup...")
        if not _run_setup(setup_args, logger=logger):
            msg = "Setup failed."
            _status(msg)
            _status("Launcher log: " + str(log_path))
            splash.close()
            _pause_if_frozen(msg)
            sys.exit(1)
        ok, missing, _ = _prereq_check(dev_mode=args.dev)
        if not ok:
            msg = "Still missing: " + ", ".join(missing)
            _status(msg)
            _status("Launcher log: " + str(log_path))
            splash.close()
            _pause_if_frozen(msg)
            sys.exit(1)

    # Launch GUI
    _status("Launching GUI...")
    splash.close()
    sys.path.insert(0, str(bot_path))
    import gui_pyside
    gui_pyside.main()


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        err_msg = str(e)
        print("Error:", err_msg)
        try:
            root = _flez_bot_root()
            logs_dir = root / "bot_runelite_IL" / "logs"
            if logs_dir.exists():
                log_hint = str(logs_dir)
            else:
                log_hint = str(root / "logs")
            _pause_if_frozen("Error: " + err_msg + "\n\nCheck logs in: " + log_hint)
        except Exception:
            _pause_if_frozen("Error: " + err_msg)
        raise
