# Packaging flez-bot

This document defines the build and release contract for installer/launcher/updater.

## Bootstrap installer model

`FlezBotSetup.exe` is intentionally small. It does not bundle the full runtime payload.

Installer flow:

1. copy bootstrap files (`flez-bot.exe`, `launcher.py`, `updater.py`, `install-runtime.ps1`)
2. create install layout directories
3. download `manifest.json`
4. download `app-full.zip`
5. verify SHA256
6. extract to `app_stage`
7. swap into `app_live`
8. write `state\state.json`
9. create shortcuts and exit

## Directory contract

Install root must contain:

- `app_live`
- `app_stage`
- `app_backup`
- `state`
- `logs`
- `cache`
- `data`
- `tmp`

## Runtime contract

Launcher behavior:

- Never installs dependencies.
- Validates `app_live` required files quickly.
- Runs update check/stage each launch.
- Prompts restart when update is staged.
- Applies staged update on restart.
- Rolls back once if post-apply healthcheck fails.
- Fails with reinstall instruction if rollback also fails.

Updater behavior:

- Uses `manifest.json` + `app-full.zip`.
- Writes state machine statuses:
  - `idle`
  - `downloaded_staged`
  - `apply_in_progress`
  - `applied_pending_healthcheck`
  - `rollback_in_progress`
  - `rolled_back`
  - `failed_requires_reinstall`

## Build commands

Run full build:

```powershell
.\bundle-setup.ps1
```

Release builds must run from an exact SemVer git tag at `HEAD` (for example `v1.2.3` or `v1.2.3-alpha.1`), unless a version is explicitly provided for local non-release testing.

Generate release artifacts only:

```powershell
.\build-release-artifacts.ps1
```

## Release publishing contract

Publish in this order:

1. `app-full.zip`
2. `app-full.zip.sha256`
3. `manifest.json.sha256`
4. `manifest.json` (last)
