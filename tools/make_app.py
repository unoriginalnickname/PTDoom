"""Turn dist/doom.html into a PC Desktop app, and fill in the Packet Tracer scripts.

Output:
  dist/app/index.html   small page
  dist/app/doom.js      engine, wasm and WAD
  dist/app/icon.png     Doomguy's status-bar face, from the WAD
  dist/install-app.js   pt/install-app.js with this repo's path filled in
  dist/doom-command.js  pt/doom-command.js with this repo's path filled in

A desktop app's page is loaded as a data: URL capped at 2 MB, but Packet
Tracer serves the app's other [gui] files separately, so the big script goes
in its own file.

Run after tools/build.py.
"""
import re
import struct
import sys

from PIL import Image

from paths import APP, DIST, DOOM_HTML, ROOT, WAD

# In the URL-loaded window, quitting navigates to a marker URL that
# pt/doom-command.js watches for. Inside a PC's window there is no watcher,
# and navigating away would leave the window blank. The shell arrives
# minified by Emscripten, so match that form.
GAME_OVER_RE = r"function gameOver\(\)\{[^}]*\}"
GAME_OVER = ("function gameOver(){statusEl.style.display='';statusEl.style.color='#ccc';"
             "statusEl.textContent='DOOM has quit. Close and reopen the app to play again.'}")

FACE = "STFST01"      # looking straight ahead, full health
ICON_SIZE = 100       # same as the built-in MQTT Client's icon
ICON_SCALE = 3

PT_SCRIPTS = ["install-app.js", "doom-command.js"]
DIST_PLACEHOLDER = "__PTDOOM_DIST__"


def split_page(page: str) -> tuple[str, str]:
    """Return (small page, engine script)."""
    m = re.search(r"<script id=mainScript>(.*?)</script>", page, re.S)
    if not m:
        sys.exit(f"mainScript not found in {DOOM_HTML}")
    # Keep the id: the engine reads getElementById("mainScript").textContent
    # at startup (only used for workers, so empty text is fine).
    shell = page[:m.start()] + '<script id=mainScript src="doom.js"></script>' + page[m.end():]
    shell, n = re.subn(GAME_OVER_RE, lambda _: GAME_OVER, shell)
    if n != 1:
        sys.exit("gameOver() not found in the page")
    return shell, m.group(1)


def wad_lumps(data: bytes) -> dict[str, bytes]:
    count, offset = struct.unpack_from("<ii", data, 4)
    lumps = {}
    for i in range(count):
        pos, size, name = struct.unpack_from("<ii8s", data, offset + 16 * i)
        lumps[name.rstrip(b"\0").decode()] = data[pos:pos + size]
    return lumps


def decode_picture(pic: bytes, palette: bytes) -> Image.Image:
    """Doom's picture format: columns of posts; a top offset of 255 ends a column."""
    width, height = struct.unpack_from("<hh", pic, 0)
    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    px = img.load()
    for x in range(width):
        pos = struct.unpack_from("<i", pic, 8 + 4 * x)[0]
        while pic[pos] != 255:
            top, length = pic[pos], pic[pos + 1]
            for i in range(length):
                c = pic[pos + 3 + i] * 3
                px[x, top + i] = (*palette[c:c + 3], 255)
            pos += length + 4
    return img


def make_icon() -> Image.Image:
    lumps = wad_lumps(WAD.read_bytes())
    face = decode_picture(lumps[FACE], lumps["PLAYPAL"][:768])
    face = face.resize((face.width * ICON_SCALE, face.height * ICON_SCALE), Image.NEAREST)
    icon = Image.new("RGBA", (ICON_SIZE, ICON_SIZE), (40, 8, 8, 255))
    icon.alpha_composite(face, ((ICON_SIZE - face.width) // 2, (ICON_SIZE - face.height) // 2))
    return icon


def main() -> int:
    for need, how in ((DOOM_HTML, "tools/build.py"), (WAD, "tools/fetch_wad.py")):
        if not need.exists():
            sys.exit(f"{need.relative_to(ROOT)} missing: run {how} first")
    APP.mkdir(parents=True, exist_ok=True)

    page, engine = split_page(DOOM_HTML.read_text(encoding="ascii"))
    (APP / "index.html").write_text(page, encoding="ascii", newline="\n")
    (APP / "doom.js").write_text(engine, encoding="ascii", newline="\n")
    make_icon().save(APP / "icon.png")

    # Packet Tracer wants forward slashes, also on Windows.
    dist = DIST.as_posix()
    for name in PT_SCRIPTS:
        text = (ROOT / "pt" / name).read_text(encoding="utf-8")
        (DIST / name).write_text(text.replace(DIST_PLACEHOLDER, dist), encoding="utf-8", newline="\n")

    for f in [APP / "index.html", APP / "doom.js", APP / "icon.png"] + [DIST / n for n in PT_SCRIPTS]:
        print(f"ok: {f.relative_to(ROOT)} ({f.stat().st_size:,} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
