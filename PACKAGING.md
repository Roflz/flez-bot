# Packaging flez-bot

This document describes where the launcher and installer expect the repo, how to build `flez-bot.exe` and `setup.exe`, and how the launcher uses `setup.ps1 -Update`.

## End user installation

For end users, installation is two steps:

1. **Run `flez-bot-setup-0.1.0.exe`** (or the current setup exe from releases). The installer will install Git and Python if needed, copy the app, run setup, and create a Start Menu shortcut.
2. **Run flez-bot** — double-click `flez-bot.exe` in the install folder, or use the Start Menu shortcut. No further setup required.

**Upgrading:** Running a newer setup.exe and choosing the default install folder (`%LOCALAPPDATA%\flez-bot`) will overwrite the previous installation. Users do not need to uninstall first.

The rest of this document is for maintainers who build the installer and launcher exe.

## Install layout

- **Install root**: The directory that contains the launcher and the repo. Typical locations:
  - `%LOCALAPPDATA%\flez-bot` (user install)
  - Or a chosen directory (e.g. `Program Files` or a portable folder).
- **Expected contents** (after setup):
  - `launcher.py` — entry script (or use `flez-bot.exe` instead).
  - `setup.ps1` — one-time setup and `-Update` for submodules.
  - `bot_runelite_IL/` — bot code (submodule).
  - `runelite/` — RuneLite (submodule).
  - `flez-bot.exe` (optional) — PyInstaller-built launcher; if missing, run `python launcher.py`.

The launcher (and `flez-bot.exe`) uses this directory as the working root: when frozen, the root is the directory containing the exe; otherwise the directory containing `launcher.py`.

## Launcher behavior

- On each start the launcher runs **`setup.ps1 -Update`** (Windows only) to fetch and update submodules to latest main/master. If that fails (e.g. no Git or no network), it logs a one-line warning and still starts the GUI.
- Then it does a quick readiness check (runelite dir, gradlew, `gui_pyside.py`, PySide6). If not ready, it runs full **`setup.ps1`** (no `-Update`) and re-checks before starting the GUI.

## Building flez-bot.exe

1. From the **flez-bot root** (same directory as `launcher.py`), in an environment with Python and PySide6 installed:
   ```powershell
   pip install pyinstaller
   python -m PyInstaller flez-bot.spec
   ```
2. Output is **`dist/flez-bot.exe`** (one-file bundle). Copy this exe into the install root next to `launcher.py`, `setup.ps1`, `bot_runelite_IL`, and `runelite`.
3. The exe assumes the app is already installed: it does not install the repo; it only runs update + readiness + GUI from that directory.

If the GUI does not start when using the exe (e.g. Qt/platform issues), run `python launcher.py` from the same directory instead.

## Building setup.exe (installer)

The installer:

1. **Installs Git and Python** if missing, using **bundled official installers** (Git for Windows and Python 3.13 from python.org), run silently. No winget or internet required during install.
2. Copies the **bundle** (repo files) into the chosen install dir (default `%LOCALAPPDATA%\flez-bot`).
3. Runs **`setup.ps1`** with a refreshed PATH so newly installed Git/Python are found (submodules, PySide6).
4. Creates a Start Menu (and optional Desktop) shortcut to `flez-bot.exe` or `python launcher.py`.

**To build the installer:**

1. **Download bundled installers** (required once per build): from repo root run:
   ```powershell
   .\installer_deps\download-installers.ps1
   ```
   This fetches the official Git and Python installers into `installer_deps\` (GitInstaller.exe, PythonInstaller.exe).

2. **Prepare the bundle** (on a machine with Git and Python):
   - Clone the flez-bot repo (with submodules) or use an existing clone.
   - From the repo root run: `.\setup.ps1`
   - Build the launcher exe (see above) and place `flez-bot.exe` in the repo root.
   - Optionally copy this entire tree to a folder (e.g. `dist\flez-bot-bundle`) for a clean bundle.

3. **Build with [Inno Setup](https://jrsoftware.org/isinfo.php)**:
   - If the bundle is the current directory (repo root):
     ```text
     iscc installer.iss
     ```
   - If the bundle is in another folder:
     ```text
     iscc /DBUNDLE_DIR=dist\flez-bot-bundle installer.iss
     ```
4. Output is **`dist/flez-bot-setup-0.1.0.exe`** (version from `installer.iss`).

## Quick test (after first install)

Once you’ve run the setup exe at least once, you can rebuild and test the launcher **without rebuilding the installer**:

From the flez-bot repo root:

```powershell
.\build-and-test.ps1
```

This builds `flez-bot.exe`, copies it to the repo root and to `%LOCALAPPDATA%\flez-bot\` (if that folder exists), and launches the app. Use this loop when fixing exe-only issues (e.g. missing hiddenimports). Use `-NoLaunch` to build and copy without starting the app.

When you’re ready to produce a new setup exe for release, run the full flow below (including `iscc installer.iss`).

## How to test (full flow)

**Prerequisites (build machine only):** Python 3 with PySide6, Git, [Inno Setup](https://jrsoftware.org/isinfo.php) (so `iscc` is in PATH).

**Step 1 — Build the launcher exe**

From the flez-bot repo root:

```powershell
pip install pyinstaller
python -m PyInstaller flez-bot.spec
copy dist\flez-bot.exe .
```

You should have `flez-bot.exe` in the repo root (alongside `launcher.py`, `setup.ps1`, `bot_runelite_IL`, `runelite`).

**Step 2 — Download bundled Git/Python installers**

From the repo root:

```powershell
.\installer_deps\download-installers.ps1
```

**Step 3 — Build the installer**

From the same repo root (the bundle is the current directory):

```powershell
iscc installer.iss
```

You should get `dist\flez-bot-setup-0.1.0.exe`.

**Step 4 — Test as end user**

1. Run **`dist\flez-bot-setup-0.1.0.exe`**. Go through the wizard (default install dir is `%LOCALAPPDATA%\flez-bot`). If Git or Python are missing, the installer will try to install them via winget.
2. When setup finishes, open the Start Menu and run **flez-bot** (or go to the install folder and double-click **flez-bot.exe**).
3. The GUI should start (update check, then launcher window). You can cancel or use it as normal.

**Optional — Clean test:** Run the setup exe on another machine (or VM) that does *not* have Git or Python, to confirm winget installs them and the app runs after install.
