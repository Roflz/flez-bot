#!/usr/bin/env python3
"""
flez-bot packaged updater.

This updater manages:
- release metadata fetch
- staged full-bundle downloads
- state machine persistence
- atomic apply/rollback directory swaps
"""

from __future__ import annotations

import argparse
import hashlib
import json
import logging
import os
import re
import shutil
import urllib.error
import urllib.request
import zipfile
from datetime import datetime, timezone
from pathlib import Path

GITHUB_OWNER = "Roflz"
GITHUB_REPO = "flez-bot"
RELEASES_API_URL = f"https://api.github.com/repos/{GITHUB_OWNER}/{GITHUB_REPO}/releases"
MANIFEST_ASSET_NAME = "manifest.json"
APP_ARTIFACT_NAME = "app-full.zip"

STATUS_IDLE = "idle"
STATUS_DOWNLOADED_STAGED = "downloaded_staged"
STATUS_APPLY_IN_PROGRESS = "apply_in_progress"
STATUS_APPLIED_PENDING_HEALTHCHECK = "applied_pending_healthcheck"
STATUS_ROLLBACK_IN_PROGRESS = "rollback_in_progress"
STATUS_ROLLED_BACK = "rolled_back"
STATUS_FAILED_REQUIRES_REINSTALL = "failed_requires_reinstall"


def result_failed(reason: str, action: str) -> str:
    return f"RESULT: FAILED | reason={reason} | action={action}"


def result_skipped(reason: str, action: str) -> str:
    return f"RESULT: SKIPPED | reason={reason} | action={action}"


def setup_logger(root: Path) -> tuple[logging.Logger, Path]:
    logs_dir = root / "logs"
    logs_dir.mkdir(parents=True, exist_ok=True)
    log_path = logs_dir / f"updater_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log"
    logger = logging.getLogger("flez_updater")
    logger.setLevel(logging.INFO)
    logger.handlers.clear()
    handler = logging.FileHandler(log_path, encoding="utf-8")
    handler.setFormatter(logging.Formatter("[%(asctime)s] %(levelname)s: %(message)s", "%H:%M:%S"))
    logger.addHandler(handler)
    return logger, log_path


def parse_version(version_text: str) -> tuple[tuple[int, ...], bool]:
    text = version_text.strip().lower()
    if text.startswith("v"):
        text = text[1:]
    prerelease = "-" in text
    number_part = text.split("-", 1)[0]
    numbers = tuple(int(part) for part in re.findall(r"\d+", number_part))
    return numbers, prerelease


def is_newer_version(latest: str, current: str) -> bool:
    latest_nums, latest_pre = parse_version(latest)
    current_nums, current_pre = parse_version(current)
    if latest_nums != current_nums:
        return latest_nums > current_nums
    if latest_pre != current_pre:
        return (not latest_pre) and current_pre
    return False


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def ensure_dirs(root: Path) -> dict[str, Path]:
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
    for path in paths.values():
        path.mkdir(parents=True, exist_ok=True)
    return paths


def state_path(root: Path) -> Path:
    return root / "state" / "state.json"


def default_state(channel: str = "alpha") -> dict:
    return {
        "schemaVersion": 1,
        "channel": channel,
        "currentVersion": "0.0.0",
        "targetVersion": None,
        "status": STATUS_IDLE,
        "artifact": None,
        "attempts": {"applyCount": 0, "rollbackCount": 0},
        "timestamps": {"updatedAt": now_iso(), "applyStartedAt": None},
        "lastError": None,
    }


def load_state(root: Path, channel: str, logger: logging.Logger) -> dict:
    sp = state_path(root)
    if not sp.exists():
        state = default_state(channel=channel)
        save_state(root, state)
        return state
    try:
        state = json.loads(sp.read_text(encoding="utf-8"))
        if not isinstance(state, dict):
            raise ValueError("state.json is not an object")
        if "status" not in state:
            raise ValueError("state.json missing status")
        return state
    except Exception as exc:
        corrupted = sp.with_name(f"state.corrupt.{datetime.now().strftime('%Y%m%d_%H%M%S')}.json")
        try:
            sp.rename(corrupted)
            logger.warning("Corrupt state.json renamed to %s: %s", corrupted, exc)
        except Exception:
            logger.warning("Corrupt state.json could not be renamed: %s", exc)
        state = default_state(channel=channel)
        save_state(root, state)
        return state


def save_state(root: Path, state: dict) -> None:
    sp = state_path(root)
    sp.parent.mkdir(parents=True, exist_ok=True)
    state.setdefault("timestamps", {})
    state["timestamps"]["updatedAt"] = now_iso()
    sp.write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")


def read_installed_version(live_dir: Path) -> str:
    version_file = live_dir / "version.json"
    if not version_file.exists():
        return "0.0.0"
    try:
        data = json.loads(version_file.read_text(encoding="utf-8"))
        return str(data.get("version", "0.0.0"))
    except Exception:
        return "0.0.0"


def fetch_releases(logger: logging.Logger) -> list[dict]:
    req = urllib.request.Request(RELEASES_API_URL, headers={"Accept": "application/vnd.github+json"})
    with urllib.request.urlopen(req, timeout=20) as resp:
        payload = resp.read().decode("utf-8", errors="replace")
    releases = json.loads(payload)
    if not isinstance(releases, list):
        raise ValueError("GitHub releases payload is not a list")
    logger.info("Fetched %d releases from GitHub API.", len(releases))
    return releases


def select_release_for_channel(releases: list[dict], channel: str) -> dict | None:
    for release in releases:
        tag = str(release.get("tag_name", "")).lower()
        prerelease = bool(release.get("prerelease", False))
        if channel == "stable":
            if not prerelease:
                return release
        else:
            if prerelease or "alpha" in tag:
                return release
    return None


def find_asset(release: dict, asset_name: str) -> dict | None:
    for asset in release.get("assets", []):
        if asset.get("name") == asset_name:
            return asset
    return None


def download_file(url: str, dest: Path, logger: logging.Logger) -> None:
    req = urllib.request.Request(url, headers={"Accept": "application/octet-stream"})
    with urllib.request.urlopen(req, timeout=120) as resp, dest.open("wb") as fh:
        total = int(resp.headers.get("Content-Length", "0") or "0")
        downloaded = 0
        while True:
            chunk = resp.read(1024 * 1024)
            if not chunk:
                break
            fh.write(chunk)
            downloaded += len(chunk)
            if total > 0:
                pct = (downloaded / total) * 100.0
                logger.info("download progress: %.1f%% (%d/%d bytes)", pct, downloaded, total)
            else:
                logger.info("download progress: %d bytes", downloaded)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate_app_dir(app_dir: Path) -> tuple[bool, str]:
    required = [
        app_dir / "version.json",
        app_dir / "runtime" / "python" / "python.exe",
        app_dir / "bot_runelite_IL" / "gui_pyside.py",
    ]
    for path in required:
        if not path.exists():
            return False, f"missing required path: {path}"
    try:
        data = json.loads((app_dir / "version.json").read_text(encoding="utf-8"))
        if not data.get("version"):
            return False, "version.json missing version field"
    except Exception as exc:
        return False, f"invalid version.json: {exc}"
    return True, ""


def extract_to_stage(zip_path: Path, stage_dir: Path, logger: logging.Logger) -> None:
    if stage_dir.exists():
        shutil.rmtree(stage_dir, ignore_errors=True)
    stage_dir.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(zip_path, "r") as zf:
        members = [m for m in zf.infolist() if not m.is_dir()]
        total = len(members)
        for i, info in enumerate(members, start=1):
            zf.extract(info, stage_dir)
            if total:
                pct = (i / total) * 100.0
                logger.info("extract progress: %.1f%% (%d/%d files)", pct, i, total)
    (stage_dir / ".staged_ok").write_text("ok\n", encoding="utf-8")


def stage_latest(root: Path, channel: str, logger: logging.Logger) -> tuple[bool, str]:
    paths = ensure_dirs(root)
    state = load_state(root, channel=channel, logger=logger)
    current_version = read_installed_version(paths["live"])
    state["currentVersion"] = current_version
    save_state(root, state)
    logger.info("Current installed version: %s", current_version)

    try:
        releases = fetch_releases(logger)
        release = select_release_for_channel(releases, channel=channel)
        if not release:
            return False, result_failed(f"no release found for channel '{channel}'", "keep_current_version")
        latest_tag = str(release.get("tag_name", "")).strip()
        logger.info("Latest release tag for channel %s: %s", channel, latest_tag)
        if not latest_tag or not is_newer_version(latest_tag, current_version):
            logger.info("No update needed.")
            return True, result_skipped("already up to date", "keep_current_version")

        manifest_asset = find_asset(release, MANIFEST_ASSET_NAME)
        if not manifest_asset:
            return False, result_failed(f"{MANIFEST_ASSET_NAME} asset missing on release", "keep_current_version")

        manifest_path = paths["cache"] / MANIFEST_ASSET_NAME
        download_file(manifest_asset["browser_download_url"], manifest_path, logger)
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

        artifact = None
        for item in manifest.get("artifacts", []):
            if item.get("name") == APP_ARTIFACT_NAME and item.get("type") == "full":
                artifact = item
                break
        if not artifact:
            return False, result_failed(f"{APP_ARTIFACT_NAME} full artifact missing in manifest", "keep_current_version")

        artifact_url = artifact.get("url")
        artifact_sha = str(artifact.get("sha256", "")).lower()
        if not artifact_url or not artifact_sha:
            return False, result_failed("artifact metadata missing url/sha256", "keep_current_version")

        artifact_path = paths["cache"] / APP_ARTIFACT_NAME
        download_file(artifact_url, artifact_path, logger)
        actual_sha = sha256_file(artifact_path).lower()
        if actual_sha != artifact_sha:
            return False, result_failed(
                f"artifact sha256 mismatch (expected={artifact_sha}, actual={actual_sha})",
                "discard_staged_update",
            )

        extract_to_stage(artifact_path, paths["stage"], logger)
        valid, reason = validate_app_dir(paths["stage"])
        if not valid:
            return False, result_failed(f"stage validation failed: {reason}", "discard_staged_update")

        state["targetVersion"] = manifest.get("version", latest_tag)
        state["status"] = STATUS_DOWNLOADED_STAGED
        state["artifact"] = {
            "name": APP_ARTIFACT_NAME,
            "url": artifact_url,
            "sha256": artifact_sha,
            "sizeBytes": artifact.get("sizeBytes", 0),
        }
        state["lastError"] = None
        save_state(root, state)
        return True, "staged"
    except urllib.error.URLError as exc:
        return False, result_failed(f"network error: {exc}", "keep_current_version")
    except Exception as exc:
        return False, result_failed(str(exc), "keep_current_version")


def apply_staged_update(root: Path, channel: str, logger: logging.Logger) -> tuple[bool, str]:
    paths = ensure_dirs(root)
    state = load_state(root, channel=channel, logger=logger)
    if state.get("status") != STATUS_DOWNLOADED_STAGED:
        return True, result_skipped("no staged update present", "keep_current_version")
    if int(state.get("attempts", {}).get("applyCount", 0)) >= 1:
        state["status"] = STATUS_FAILED_REQUIRES_REINSTALL
        state["lastError"] = "apply loop protection triggered (max apply attempts reached)"
        save_state(root, state)
        return False, result_failed("apply loop protection triggered", "reinstall_required")

    stage = paths["stage"]
    live = paths["live"]
    backup = paths["backup"]
    valid, reason = validate_app_dir(stage)
    if not valid:
        return False, result_failed(f"cannot apply invalid stage: {reason}", "rollback_or_reinstall")

    try:
        state["status"] = STATUS_APPLY_IN_PROGRESS
        state["attempts"]["applyCount"] = int(state["attempts"].get("applyCount", 0)) + 1
        state["timestamps"]["applyStartedAt"] = now_iso()
        save_state(root, state)

        if backup.exists():
            shutil.rmtree(backup, ignore_errors=True)
        if live.exists():
            os.replace(str(live), str(backup))
        os.replace(str(stage), str(live))
        state["status"] = STATUS_APPLIED_PENDING_HEALTHCHECK
        save_state(root, state)
        return True, "applied"
    except Exception as exc:
        state["lastError"] = str(exc)
        save_state(root, state)
        return False, result_failed(f"apply failed: {exc}", "rollback_or_reinstall")


def rollback(root: Path, channel: str, logger: logging.Logger) -> tuple[bool, str]:
    paths = ensure_dirs(root)
    state = load_state(root, channel=channel, logger=logger)
    backup = paths["backup"]
    live = paths["live"]
    if int(state.get("attempts", {}).get("rollbackCount", 0)) >= 1:
        state["status"] = STATUS_FAILED_REQUIRES_REINSTALL
        state["lastError"] = "rollback loop protection triggered (max rollback attempts reached)"
        save_state(root, state)
        return False, result_failed("rollback loop protection triggered", "reinstall_required")
    if not backup.exists():
        state["status"] = STATUS_FAILED_REQUIRES_REINSTALL
        state["lastError"] = "backup missing during rollback"
        save_state(root, state)
        return False, result_failed("backup missing during rollback", "reinstall_required")

    valid, reason = validate_app_dir(backup)
    if not valid:
        state["status"] = STATUS_FAILED_REQUIRES_REINSTALL
        state["lastError"] = f"invalid backup: {reason}"
        save_state(root, state)
        return False, result_failed(f"invalid backup: {reason}", "reinstall_required")

    try:
        state["status"] = STATUS_ROLLBACK_IN_PROGRESS
        state["attempts"]["rollbackCount"] = int(state["attempts"].get("rollbackCount", 0)) + 1
        save_state(root, state)
        failed_live = paths["tmp"] / "failed_live"
        if failed_live.exists():
            shutil.rmtree(failed_live, ignore_errors=True)
        if live.exists():
            os.replace(str(live), str(failed_live))
        os.replace(str(backup), str(live))
        state["status"] = STATUS_ROLLED_BACK
        save_state(root, state)
        return True, "rolled_back"
    except Exception as exc:
        state["status"] = STATUS_FAILED_REQUIRES_REINSTALL
        state["lastError"] = f"rollback failed: {exc}"
        save_state(root, state)
        return False, result_failed(f"rollback failed: {exc}", "reinstall_required")


def main() -> int:
    parser = argparse.ArgumentParser(description="flez-bot packaged updater")
    parser.add_argument("--root", default=str(Path(__file__).resolve().parent))
    parser.add_argument("--channel", default="alpha", choices=["alpha", "stable"])
    parser.add_argument("--mode", default="check-stage", choices=["check-stage", "apply", "rollback"])
    args = parser.parse_args()
    root = Path(args.root).resolve()

    logger, log_path = setup_logger(root)
    logger.info("Updater starting. Root=%s mode=%s channel=%s", root, args.mode, args.channel)
    logger.info("Updater log path: %s", log_path)

    if args.mode == "check-stage":
        ok, detail = stage_latest(root, channel=args.channel, logger=logger)
    elif args.mode == "apply":
        ok, detail = apply_staged_update(root, channel=args.channel, logger=logger)
    else:
        ok, detail = rollback(root, channel=args.channel, logger=logger)

    if ok:
        logger.info("Updater finished successfully: %s", detail)
        return 0
    logger.error("Updater failed: %s", detail)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
