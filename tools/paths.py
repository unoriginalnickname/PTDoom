"""Where things live, shared by the tools."""
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
WAD = ROOT / "wad" / "doom1.wad"
DIST = ROOT / "dist"
DOOM_HTML = DIST / "doom.html"  # the whole game in one page, from build.py
APP = DIST / "app"              # the Desktop app's files, from make_app.py
