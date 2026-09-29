"""Make the Desktop app's files and the playable page, and fill in the Packet Tracer scripts.

Output:
  dist/app/index.html   small page
  dist/app/doom.js      engine and wasm, no game data
  dist/app/wad.js       the WAD, as window.DOOM_WAD (see web/shell.html)
  dist/app/icon.png     Doomguy's status-bar face, from the WAD
  dist/doom.html        engine and WAD in one page, for doom-command.js or a browser
  dist/install-app.js   pt/install-app.js with this repo's path filled in
  dist/doom-command.js  pt/doom-command.js with this repo's path filled in

A desktop app's page is loaded as a data: URL capped at 2 MB, but Packet
Tracer serves the app's other [gui] files separately, so the engine and the
WAD go in their own files.

Run after tools/build.py, with a WAD in wad/ (tools/fetch_wad.py gets the
shareware one).
"""
import base64
import json
import re
import struct
import sys

from PIL import Image

from paths import APP, DIST, DOOM_HTML, ENGINE_HTML, ROOT, WAD

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


def split_page(page: str) -> tuple[str, str, str]:
    """Return (page before the engine, engine script, page after the engine)."""
    m = re.search(r"<script id=mainScript>(.*?)</script>", page, re.S)
    if not m:
        sys.exit(f"mainScript not found in {ENGINE_HTML}")
    return page[:m.start()], m.group(1), page[m.end():]


def wad_script(wad: bytes, name: str) -> str:
    data = base64.b64encode(wad).decode("ascii")
    return "window.DOOM_WAD=" + json.dumps({"name": name, "data": data}) + ";\n"


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


def make_icon(wad: bytes) -> Image.Image:
    lumps = wad_lumps(wad)
    face = decode_picture(lumps[FACE], lumps["PLAYPAL"][:768])
    face = face.resize((face.width * ICON_SCALE, face.height * ICON_SCALE), Image.NEAREST)
    icon = Image.new("RGBA", (ICON_SIZE, ICON_SIZE), (40, 8, 8, 255))
    icon.alpha_composite(face, ((ICON_SIZE - face.width) // 2, (ICON_SIZE - face.height) // 2))
    return icon


def write(path, text: str) -> None:
    path.write_text(text, encoding="ascii", newline="\n")


def main() -> int:
    for need, how in ((ENGINE_HTML, "tools/build.py"), (WAD, "tools/fetch_wad.py")):
        if not need.exists():
            sys.exit(f"{need.relative_to(ROOT)} missing: run {how} first")
    wad = WAD.read_bytes()
    wad_js = wad_script(wad, WAD.name.lower())
    before, engine, after = split_page(ENGINE_HTML.read_text(encoding="ascii"))

    # The app: the engine reads getElementById("mainScript").textContent at
    # startup (only used for workers, so empty text is fine): keep the id.
    APP.mkdir(parents=True, exist_ok=True)
    app_page = before + '<script src="wad.js"></script><script id=mainScript src="doom.js"></script>' + after
    app_page, n = re.subn(GAME_OVER_RE, lambda _: GAME_OVER, app_page)
    if n != 1:
        sys.exit("gameOver() not found in the page")
    write(APP / "index.html", app_page)
    write(APP / "doom.js", engine)
    write(APP / "wad.js", wad_js)
    make_icon(wad).save(APP / "icon.png")

    # One page with everything inline, for the URL-loaded window.
    write(DOOM_HTML, before + "<script>" + wad_js + "</script><script id=mainScript>" + engine + "</script>" + after)

    # Packet Tracer wants forward slashes, also on Windows.
    dist = DIST.as_posix()
    for name in PT_SCRIPTS:
        text = (ROOT / "pt" / name).read_text(encoding="utf-8")
        (DIST / name).write_text(text.replace(DIST_PLACEHOLDER, dist), encoding="utf-8", newline="\n")

    outputs = [APP / f for f in ("index.html", "doom.js", "wad.js", "icon.png")] + [DOOM_HTML] + [DIST / n for n in PT_SCRIPTS]
    for f in outputs:
        print(f"ok: {f.relative_to(ROOT)} ({f.stat().st_size:,} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
