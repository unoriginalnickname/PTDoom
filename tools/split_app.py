"""Split dist/doom.html into a PC Desktop app's page and script.

Output: dist/app/index.html (small page) and dist/app/doom.js (engine, wasm
and WAD). A desktop app's page is loaded as a data: URL capped at 2 MB, but
Packet Tracer serves the app's other [gui] files separately, so the big
script goes in its own file.

Run after tools/build.py.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "dist" / "doom.html"
OUT = ROOT / "dist" / "app"

# In the URL-loaded window, quitting navigates to a marker URL that
# pt/doom-command.js watches for. Inside a PC's window there is no watcher,
# and navigating away would leave the window blank.
# The shell arrives minified by Emscripten, so match that form.
GAME_OVER_RE = r"function gameOver\(\)\{[^}]*\}"
GAME_OVER = ("function gameOver(){statusEl.style.display='';statusEl.style.color='#ccc';"
             "statusEl.textContent='DOOM has quit. Close and reopen the app to play again.'}")


def main() -> int:
    page = SRC.read_text(encoding="ascii")
    m = re.search(r"<script id=mainScript>(.*?)</script>", page, re.S)
    if not m:
        sys.exit("mainScript not found in dist/doom.html")
    # Keep the id: the engine reads getElementById("mainScript").textContent
    # at startup (only used for workers, so empty text is fine).
    shell = page[:m.start()] + '<script id=mainScript src="doom.js"></script>' + page[m.end():]
    shell, n = re.subn(GAME_OVER_RE, lambda _: GAME_OVER, shell)
    if n != 1:
        sys.exit("gameOver() not found in the shell")
    OUT.mkdir(exist_ok=True)
    (OUT / "index.html").write_text(shell, encoding="ascii", newline="\n")
    (OUT / "doom.js").write_text(m.group(1), encoding="ascii", newline="\n")
    for f in ("index.html", "doom.js"):
        print(f"ok: {OUT / f} ({(OUT / f).stat().st_size // 1024} KB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
