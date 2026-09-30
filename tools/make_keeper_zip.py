"""Make a Dungeon Keeper zip for the DOS app's games window, from your own copy.

    python tools/make_keeper_zip.py "D:/EAGames/Dungeon Keeper/DATA"

The folder is the one holding KEEPER.EXE in an installed copy (tested with EA's
Dungeon Keeper Gold, which runs it in DOSBox). The zip, dosgames/keeper/keeper.zip,
holds the game as a full ("MAX") install without the CD: DOSBox and its
settings and the CD image (GAME.DAT, GAME.INS) stay out. The CD's music,
keeper02.ogg to keeper07.ogg (EA's copies of audio tracks 2 to 7), goes in as
CDAUDIO/TRACK02.OGG and on, which the DOS app plays as the CD's audio tracks.
Add it in the games window under the name KEEPER, program KEEPER (both guessed
from the zip's name); Deeper Dungeons is DEEPER in the same folder.

KEEPER.CFG is rewritten to INSTALL_PATH=C:\\KEEPER: the game's CD check reads
INSTALL_PATH\\LDATA\\DKWIND00.DAT, and the path has to be exactly the game's folder
on drive C:. EA's C:\\ (DOSBox's own drive) would give C:\\\\LDATA, which FreeDOS
rejects, and the game then waits for its CD forever.
"""
import re
import sys
import zipfile
from pathlib import Path

from paths import ROOT

NAME = "KEEPER"
SKIP_DIRS = {"DOSBOX", "SAVES"}
SKIP_FILES = {"GAME.DAT", "GAME.INS", "THUMBS.DB"}
SKIP_TYPES = {".conf"}
CFG = f"INSTALL_PATH=C:\\{NAME}\r\nINSTALL_TYPE=MAX\r\nLANGUAGE=ENG\r\n"


def main() -> int:
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    src = Path(sys.argv[1])
    if not (src / "KEEPER.EXE").exists():
        sys.exit(f"no KEEPER.EXE in {src}: give the folder that holds it")
    out = ROOT / "dosgames" / "keeper" / "keeper.zip"
    out.parent.mkdir(parents=True, exist_ok=True)
    count = size = tracks = 0
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for f in sorted(src.rglob("*")):
            rel = f.relative_to(src)
            if f.is_dir() or rel.parts[0].upper() in SKIP_DIRS:
                continue
            if f.name.upper() in SKIP_FILES or f.suffix.lower() in SKIP_TYPES:
                continue
            data = CFG.encode("ascii") if f.name.upper() == "KEEPER.CFG" else f.read_bytes()
            name = rel.as_posix()
            track = re.fullmatch(r"keeper(\d\d)\.ogg", f.name, re.IGNORECASE)
            if track and len(rel.parts) == 1:
                name = f"CDAUDIO/TRACK{track[1]}.OGG"
                tracks += 1
            elif f.suffix.lower() == ".ogg":
                continue
            z.writestr(name, data)
            count += 1
            size += len(data)
    print(f"ok: {out.relative_to(ROOT)}: {count} files, {size / 1048576:.0f} MB, "
          f"{out.stat().st_size / 1048576:.0f} MB zipped")
    print(f"CD music: {tracks} tracks" if tracks else "No CD music found (keeper02.ogg...): the game will be silent")
    print(f"In the games window: Name {NAME}, Program {NAME}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
