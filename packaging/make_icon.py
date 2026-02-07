"""
Generate packaging/icon.ico from bot_runelite_IL/gui/icon.png for the exe and installer.
Run from repo root: python packaging/make_icon.py
Requires: pip install Pillow
"""
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    raise SystemExit("Pillow required. Run: pip install Pillow")

repo_root = Path(__file__).resolve().parent.parent
src = repo_root / "bot_runelite_IL" / "gui" / "icon.png"
out_ico = repo_root / "packaging" / "icon.ico"

if not src.is_file():
    raise SystemExit(f"Source icon not found: {src}")

img = Image.open(src)
if img.mode != "RGBA":
    img = img.convert("RGBA")
sizes = [(16, 16), (32, 32), (48, 48), (64, 64), (256, 256)]
img.save(str(out_ico), format="ICO", sizes=sizes)
print(f"Wrote {out_ico}")
