"""Where things live, shared by the tools."""
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
WAD = ROOT / "wad" / "doom1.wad"
DIST = ROOT / "dist"
ENGINE_HTML = DIST / "engine.html"  # engine without game data, from build.py
DOOM_HTML = DIST / "doom.html"      # engine plus WAD in one page, from make_app.py
APP = DIST / "app"                  # the Desktop app's files, from make_app.py
