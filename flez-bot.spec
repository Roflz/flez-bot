# PyInstaller spec for flez-bot.exe (launcher).
# Run from flez-bot root: pyinstaller flez-bot.spec
# Output: dist/flez-bot/flez-bot.exe (copy into install dir alongside bot_runelite_IL, runelite).
# When run, the exe uses its directory as the flez-bot root (see launcher._flez_bot_root).

# -*- mode: python ; coding: utf-8 -*-
import sys

block_cipher = None

a = Analysis(
    ['launcher.py'],
    pathex=[],
    binaries=[],
    datas=[],
    hiddenimports=[
        'PySide6',
        'PySide6.QtCore',
        'PySide6.QtGui',
        'PySide6.QtWidgets',
        'pkgutil',   # used by plan discovery (bot_runelite_IL loaded from disk)
        'psutil',    # used by client_detector_pyside
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.zipfiles,
    a.datas,
    [],
    name='flez-bot',
    icon='packaging/icon.ico',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=False,  # No CMD window; GUI only
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
