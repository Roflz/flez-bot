#!/usr/bin/env python3
"""
flez-bot launcher contract implementation.

- Never installs dependencies.
- Validates packaged app layout quickly.
- Checks/stages updates on every launch.
- Applies staged updates only on restart decision.
"""

from __future__ import annotations

import json
import logging
import os
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

STATUS_IDLE = "idle"
STATUS_DOWNLOADED_STAGED = "downloaded_staged"
STATUS_APPLIED_PENDING_HEALTHCHECK = "applied_pending_healthcheck"
STATUS_ROLLED_BACK = "rolled_back"
STATUS_FAILED_REQUIRES_REINSTALL = "failed_requires_reinstall"


def _root() -> Path:
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parent


def _ensure_layout(root: Path) -> dict[str, Path]:
    paths = {
        "live": root / "app_live",
        "stage": root / "app_stage",
        "backup": root / "app_backup",
        "state_dir": root / "state",
        "logs": root / "logs",
        "cache": root / "cache",
        "data": root / "data",
        "tmp": root / "tmp",
    }
    for p in paths.values():
        p.mkdir(parents=True, exist_ok=True)
    return paths


def _setup_logger(root: Path) -> tuple[logging.Logger, Path]:
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


def _state_path(root: Path) -> Path:
    return root / "state" / "state.json"


def _default_state() -> dict:
    return {
        "schemaVersion": 1,
        "channel": "alpha",
        "currentVersion": "0.0.0",
        "targetVersion": None,
        "status": STATUS_IDLE,
        "artifact": None,
        "attempts": {"applyCount": 0, "rollbackCount": 0},
        "timestamps": {"updatedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"), "applyStartedAt": None},
        "lastError": None,
    }


def _load_state(root: Path, logger: logging.Logger) -> dict:
    sp = _state_path(root)
    if not sp.exists():
        state = _default_state()
        _save_state(root, state)
        return state
    try:
        state = json.loads(sp.read_text(encoding="utf-8"))
        if not isinstance(state, dict):
            raise ValueError("state.json is not an object")
        return state
    except Exception as exc:
        logger.error("state.json invalid: %s", exc)
        state = _default_state()
        _save_state(root, state)
        return state


def _save_state(root: Path, state: dict) -> None:
    state.setdefault("timestamps", {})
    state["timestamps"]["updatedAt"] = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    _state_path(root).write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")


def _validate_app_dir(app_dir: Path) -> tuple[bool, str]:
    required = [
        app_dir / "version.json",
        app_dir / "runtime" / "python" / "python.exe",
        app_dir / "bot_runelite_IL" / "gui_pyside.py",
    ]
    for path in required:
        if not path.exists():
            return False, f"required file missing: {path}"
    try:
        data = json.loads((app_dir / "version.json").read_text(encoding="utf-8"))
        if not data.get("version"):
            return False, "version.json missing version"
    except Exception as exc:
        return False, f"version.json parse failed: {exc}"
    try:
        r = subprocess.run(
            [str(app_dir / "runtime" / "python" / "python.exe"), "--version"],
            capture_output=True,
            text=True,
            timeout=20,
        )
        if r.returncode != 0:
            return False, f"python --version failed with exit {r.returncode}"
    except Exception as exc:
        return False, f"python runtime check failed: {exc}"
    return True, ""


def _run_updater(root: Path, mode: str, channel: str, logger: logging.Logger) -> tuple[bool, str]:
    updater = root / "updater.py"
    if not updater.exists():
        return False, "updater.py not found"
    python_exe = root / "app_live" / "runtime" / "python" / "python.exe"
    if not python_exe.exists():
        resolved = shutil.which("python")
        if not resolved:
            return False, "python runtime unavailable for updater"
        python_exe = Path(resolved)
    cmd = [str(python_exe), str(updater), "--root", str(root), "--channel", channel, "--mode", mode]
    try:
        r = subprocess.run(cmd, cwd=str(root), capture_output=True, text=True, timeout=600)
        logger.info("updater cmd: %s", " ".join(cmd))
        if r.stdout:
            logger.info("updater stdout: %s", r.stdout.strip())
        if r.stderr:
            logger.warning("updater stderr: %s", r.stderr.strip())
        if r.returncode != 0:
            detail = r.stderr.strip() or r.stdout.strip() or f"exit={r.returncode}"
            return False, detail
        return True, r.stdout.strip()
    except Exception as exc:
        return False, str(exc)


def _read_live_version(paths: dict[str, Path]) -> str:
    version_file = paths["live"] / "version.json"
    if not version_file.exists():
        return "0.0.0"
    try:
        data = json.loads(version_file.read_text(encoding="utf-8"))
        return str(data.get("version", "0.0.0"))
    except Exception:
        return "0.0.0"


def _health_marker(root: Path, version: str) -> None:
    marker = root / "state" / "health.json"
    marker.write_text(
        json.dumps(
            {
                "healthyVersion": version,
                "timestampUtc": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )


def _prompt_restart_now() -> bool:
    if sys.platform != "win32":
        return False
    try:
        import ctypes

        title = "Update ready"
        body = (
            "A flez-bot update is ready.\n\n"
            "Restart now to apply it?\n\n"
            "Choose Yes to restart now, or No to continue and apply later."
        )
        result = ctypes.windll.user32.MessageBoxW(0, body, title, 0x04 | 0x20)
        return result == 6
    except Exception:
        return False


def _launch_live(paths: dict[str, Path], logger: logging.Logger) -> None:
    live = paths["live"]
    py = live / "runtime" / "python" / "python.exe"
    entry = live / "bot_runelite_IL" / "gui_pyside.py"
    if not py.exists() or not entry.exists():
        raise RuntimeError("No valid app entry found in app_live")
    logger.info("Launching GUI from app_live using bundled python.")
    os.execv(str(py), [str(py), str(entry)])


def _fail_with_reinstall(msg: str, log_path: Path, title: str = "flez-bot needs reinstall") -> None:
    text = (
        "flez-bot could not start safely.\n\n"
        f"Reason: {msg}\n"
        "Action: Reinstall flez-bot.\n\n"
        f"Log file:\n{log_path}"
    )
    print(text)
    if sys.platform == "win32":
        try:
            import ctypes

            ctypes.windll.user32.MessageBoxW(0, text, title, 0x10)
        except Exception:
            pass
    raise SystemExit(1)


def main() -> int:
    root = _root()
    paths = _ensure_layout(root)
    logger, log_path = _setup_logger(root)
    logger.info("Launcher start. root=%s", root)
    logger.info("Launcher log path: %s", log_path)

    state = _load_state(root, logger)
    channel = str(state.get("channel", "alpha") or "alpha")
    logger.info("Current state status: %s", state.get("status"))

    # Recover from failed apply on previous run.
    if state.get("status") == STATUS_APPLIED_PENDING_HEALTHCHECK:
        ok, reason = _validate_app_dir(paths["live"])
        if ok:
            version = _read_live_version(paths)
            _health_marker(root, version)
            state["status"] = STATUS_IDLE
            state["currentVersion"] = version
            _save_state(root, state)
            logger.info("Previous applied version passed healthcheck: %s", version)
        else:
            logger.error("Healthcheck failed after apply: %s", reason)
            rb_ok, rb_detail = _run_updater(root, "rollback", channel, logger)
            if not rb_ok:
                state = _load_state(root, logger)
                state["status"] = STATUS_FAILED_REQUIRES_REINSTALL
                state["lastError"] = f"rollback failed after healthcheck failure: {rb_detail}"
                _save_state(root, state)
                _fail_with_reinstall(
                    f"Update healthcheck failed and rollback also failed ({rb_detail}).",
                    log_path,
                    "Update recovery failed",
                )
            logger.warning("Rolled back to backup due to failed healthcheck.")

    # Baseline validity; one automatic repair attempt if invalid.
    live_ok, live_reason = _validate_app_dir(paths["live"])
    if not live_ok:
        logger.warning("Live install invalid: %s", live_reason)
        stage_ok, stage_detail = _run_updater(root, "check-stage", channel, logger)
        if not stage_ok:
            _fail_with_reinstall(
                f"Automatic repair stage failed ({stage_detail}).",
                log_path,
            )
        apply_ok, apply_detail = _run_updater(root, "apply", channel, logger)
        if not apply_ok:
            _fail_with_reinstall(
                f"Automatic repair apply failed ({apply_detail}).",
                log_path,
            )
        live_ok, live_reason = _validate_app_dir(paths["live"])
        if not live_ok:
            _fail_with_reinstall(
                f"Install remains invalid after repair ({live_reason}).",
                log_path,
            )

    # Per-launch update check and stage.
    stage_ok, stage_detail = _run_updater(root, "check-stage", channel, logger)
    if not stage_ok:
        logger.warning(
            "RESULT: FAILED | reason=%s | action=continue_with_current_version",
            stage_detail,
        )
    else:
        state = _load_state(root, logger)
        if state.get("status") == STATUS_DOWNLOADED_STAGED:
            logger.info("Staged update detected.")
            if _prompt_restart_now():
                logger.info("User chose restart now; applying staged update.")
                apply_ok, apply_detail = _run_updater(root, "apply", channel, logger)
                if not apply_ok:
                    logger.error(
                        "RESULT: FAILED | reason=%s | action=continue_with_current_version",
                        apply_detail,
                    )
                else:
                    logger.info("Update applied; launching updated app.")
            else:
                logger.info("User chose Later for staged update.")

    # Mark health for the currently running live version.
    version = _read_live_version(paths)
    _health_marker(root, version)
    state = _load_state(root, logger)
    if state.get("status") in (STATUS_ROLLED_BACK, STATUS_APPLIED_PENDING_HEALTHCHECK):
        state["status"] = STATUS_IDLE
        state["currentVersion"] = version
        _save_state(root, state)
    logger.info("Launching app_live version: %s", version)
    _launch_live(paths, logger)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
