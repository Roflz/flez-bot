App icon: bot_runelite_IL/gui/icon.png is used in the client window and menu bar.
packaging/icon.ico is generated from it for the exe and installer.

To regenerate icon.ico after changing the PNG:
  python packaging/make_icon.py

Build (PyInstaller and iscc) uses packaging/icon.ico; run make_icon.py first if you changed the PNG.
