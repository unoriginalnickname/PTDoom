"""Make the DOS Desktop app's files: js-dos, the emulator and a game bundle.

Output, in dist/dosapp/:
  index.html     small page
  jsdos.js       web/ptdos-shim.js, js-dos's CSS and js-dos itself, patched
  emulators.js   emulators.js with the DOSBox and libzip .js/.wasm embedded
  game.js        the game bundle (.jsdos), embedded
  icon.png       a DOS prompt
and dist/install-dos-app.js, pt/install-dos-app.js with this repo's path filled in.

js-dos comes from vendor/js-dos/ (npm package js-dos, dist/ folder).
The game is a .jsdos bundle given on the command line, or, with no argument,
shareware DOOM built from dosgames/doom/ (see NOTES.md for where it comes from).
Open dist/dosapp/index.html in a Packet Tracer web view to test it without
installing.
"""
import base64
import io
import json
import sys
import zipfile

from PIL import Image, ImageDraw, ImageFont

from paths import DIST, ROOT

JSDOS = ROOT / "vendor" / "js-dos"
OUT = DIST / "dosapp"
DOOM_DIR = ROOT / "dosgames" / "doom"

EMULATOR_FILES = ["wdosbox.js", "wdosbox.wasm", "wlibzip.js", "wlibzip.wasm"]

# (what, from, to): each must match exactly once.
JSDOS_PATCHES = [
    # The AudioWorklet player plays high-pitched and choppy in Packet Tracer;
    # the older ScriptProcessor player sounds right.
    ("AudioWorklet off", "audioWorklet:!0", "audioWorklet:!1"),
    # Give the ScriptProcessor player more room, against stutter.
    ("audio queue", "r.length()<6144&&r.push(e)", "r.length()<16384&&r.push(e)"),
    ("audio block", "createScriptProcessor(2048,0,1)", "createScriptProcessor(4096,0,1)"),
    ("audio start", "s=o>=2048", "s=o>=6144"),
]

# Names the page mentions in its HTML. Packet Tracer rewrites every
# occurrence of a [gui] file's name in the page, even inside strings, so the
# page's own script must not contain these, and the bundle isn't "game.jsdos"
# (which contains "game.js").
BUNDLE_NAME = "bundle.jsdos"

PAGE = """<!doctype html>
<html><head><meta charset="utf-8">
<style>
html,body{margin:0;height:100%;background:#000;overflow:hidden}
#dos{width:100%;height:100%}
#log{position:fixed;bottom:0;left:0;margin:0;color:#8f8;font:11px monospace;background:rgba(0,0,0,.6);max-height:25%;overflow:auto;z-index:99}
</style>
</head><body><div id="dos"></div><pre id="log"></pre>
<script>
var logEl=document.getElementById("log");
function log(m){logEl.textContent+=m+"\\n";}
window.onerror=function(m,s,l){log("error: "+m+" ("+l+")");};
window.addEventListener("unhandledrejection",function(e){log("error: "+(e.reason&&e.reason.message||e.reason));});
</script>
<script src="jsdos.js"></script>
<script id="emulators-js" src="emulators.js"></script>
<script src="game.js"></script>
<script>
(function(){
  var worker=true;
  try{
    emulators.pathPrefix=PTDOS_PREFIX;
    emulators.pathSuffix="";
    Dos(document.getElementById("dos"),{url:PTDOS_PREFIX+"BUNDLE",pathPrefix:PTDOS_PREFIX,
      workerThread:worker,autoStart:true,kiosk:true,backend:"dosbox",backendLocked:true,noCursor:false});
    log("js-dos started, worker "+worker);
    setTimeout(function(){logEl.style.display="none";},15000);
  }catch(e){log("error: "+e.message);}
})();
</script>
</body></html>
""".replace("BUNDLE", BUNDLE_NAME)

DOOM_CONF = """[sdl]
autolock=false
[cpu]
core=auto
cputype=auto
cycles=fixed 15000
[sblaster]
sbtype=sb16
sbbase=220
irq=7
dma=1
hdma=5
oplmode=auto
[autoexec]
@echo off
mount c .
c:
doom.exe
"""

# DOOM's settings: Sound Blaster at 220/7/1 for effects, AdLib for music
# (both through DOSBox's SB16), no mouse (clicks would fight over pointer
# lock), volumes below full (full clipped on gunshots).
DOOM_CFG = """mouse_sensitivity 5
sfx_volume 5
music_volume 6
show_messages 1
use_mouse 0
use_joystick 0
snd_channels 8
snd_musicdevice 3
snd_sfxdevice 3
snd_sbport 544
snd_sbirq 7
snd_sbdma 1
snd_mport 816
screenblocks 10
detaillevel 0
usegamma 0
"""


def ascii_js(text: str) -> str:
    """Escape non-ASCII characters; valid in JS strings, regexes, comments and identifiers."""
    out = []
    for ch in text:
        c = ord(ch)
        if c < 128:
            out.append(ch)
        elif c < 0x10000:
            out.append("\\u%04x" % c)
        else:
            c -= 0x10000
            out.append("\\u%04x\\u%04x" % (0xD800 + (c >> 10), 0xDC00 + (c & 0x3FF)))
    return "".join(out)


def embed(files: dict[str, bytes]) -> str:
    lines = ["window.PTDOS_FILES=window.PTDOS_FILES||{};"]
    for name, data in files.items():
        lines.append("PTDOS_FILES[%s]=\"%s\";" % (json.dumps(name), base64.b64encode(data).decode("ascii")))
    return "\n".join(lines) + "\n"


def doom_bundle() -> bytes:
    need = [DOOM_DIR / "DOOM.EXE", DOOM_DIR / "DOOM1.WAD"]
    for f in need:
        if not f.exists():
            sys.exit(f"{f.relative_to(ROOT)} missing: unpack shareware DOOM 1.9 there (see NOTES.md)")
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr(".jsdos/dosbox.conf", DOOM_CONF)
        for f in need:
            z.write(f, f.name)
        z.writestr("DEFAULT.CFG", DOOM_CFG)
    return buf.getvalue()


def patched_jsdos() -> str:
    js = (JSDOS / "js-dos.js").read_text(encoding="utf-8")
    for what, old, new in JSDOS_PATCHES:
        n = js.count(old)
        if n != 1:
            sys.exit(f"js-dos patch '{what}': found {n} times, expected once (js-dos version changed?)")
        js = js.replace(old, new)
    return js


def make_icon() -> Image.Image:
    """A DOS prompt, 100 px like the other app icons."""
    icon = Image.new("RGBA", (100, 100), (0, 0, 170, 255))
    draw = ImageDraw.Draw(icon)
    try:
        font = ImageFont.truetype("consolab.ttf", 26)
    except OSError:
        font = ImageFont.load_default()
    draw.text((50, 50), "C:\\>_", font=font, fill=(230, 230, 230, 255), anchor="mm")
    return icon


def write(name: str, text: str) -> None:
    (OUT / name).write_text(text, encoding="ascii", newline="\n")


def main() -> int:
    if not (JSDOS / "js-dos.js").exists():
        sys.exit("vendor/js-dos missing: npm pack js-dos, then copy the package's dist/ there")
    game = sys.argv[1] if len(sys.argv) > 1 else None
    bundle = open(game, "rb").read() if game else doom_bundle()

    OUT.mkdir(parents=True, exist_ok=True)
    shim = (ROOT / "web" / "ptdos-shim.js").read_text(encoding="utf-8")
    css = (JSDOS / "js-dos.css").read_text(encoding="utf-8")
    css_js = ("(function(){var s=document.createElement('style');s.textContent=%s;"
              "document.head.appendChild(s);})();\n" % json.dumps(css))
    write("jsdos.js", ascii_js(shim + "\n" + css_js + patched_jsdos()))

    emu = {n: (JSDOS / "emulators" / n).read_bytes() for n in EMULATOR_FILES}
    write("emulators.js", embed(emu) + ascii_js((JSDOS / "emulators" / "emulators.js").read_text(encoding="utf-8")))
    write("game.js", embed({BUNDLE_NAME: bundle}))
    write("index.html", PAGE)
    make_icon().save(OUT / "icon.png")

    # Packet Tracer wants forward slashes, also on Windows.
    installer = (ROOT / "pt" / "install-dos-app.js").read_text(encoding="utf-8")
    (DIST / "install-dos-app.js").write_text(installer.replace("__PTDOOM_DIST__", DIST.as_posix()), encoding="utf-8", newline="\n")

    outputs = [OUT / f for f in ("index.html", "jsdos.js", "emulators.js", "game.js", "icon.png")] + [DIST / "install-dos-app.js"]
    for f in outputs:
        print(f"ok: {f.relative_to(ROOT)} ({f.stat().st_size:,} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
