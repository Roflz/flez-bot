# flez-bot

This repository ships a bootstrap installer + launcher for a packaged `flez-bot` runtime.

## Product contract (implemented)

- No `setup.ps1` workflow in packaged or developer mode.
- Installer only:
  - places bootstrap files
  - downloads/verifies release artifact
  - installs to `app_live`
  - creates shortcuts
  - writes install logs
- Launcher only:
  - validates required packaged files
  - checks/stages updates each launch
  - applies staged updates on restart decision
  - launches app
- Updater only:
  - stages/downloads full bundle
  - applies atomic swap with backup
  - rolls back on failed healthcheck

## Install layout

Installed root layout:

- `app_live/`
- `app_stage/`
- `app_backup/`
- `state/`
- `logs/`
- `cache/`
- `data/`
- `tmp/`

## Build

Use:

```powershell
.\bundle-setup.ps1
```

This runs:

1. icon generation
2. launcher exe build
3. release artifact build (`app-full.zip`, `manifest.json`, `.sha256`)
4. Inno Setup build (`dist\setup.exe`)

## Release artifacts

Required release assets:

- `app-full.zip`
- `app-full.zip.sha256`
- `manifest.json`
- `manifest.json.sha256`

Publish order: artifact(s) first, `manifest.json` last.

## Logs

- Installer: `logs\install.log`
- Launcher: `logs\launcher_YYYYMMDD_HHMMSS.log`
- Updater: `logs\updater_YYYYMMDD_HHMMSS.log`
