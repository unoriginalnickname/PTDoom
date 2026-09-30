"""Make the DOS Desktop app's files: v86, FreeDOS and games.

Output, in dist/v86app/:
  index.html   small page
  ptdos.js     web/v86-dos.js: unzips the games, builds drive C:, boots v86
  libv86.js    v86
  v86data.js   BIOS, VGA BIOS, FreeDOS floppy, v86.wasm and opl.wasm, as base64
  g1.js        a game (a .zip, as base64) for window.PTDOS_GAMES
  games.json   the list of installed games, for the installer page
  icon.png     a DOS prompt
and dist/install-v86-app.js, pt/install-v86-app.js with this repo's path filled in.

With no argument the one game is shareware DOOM from dosgames/doom/. With
--no-game there are none, and installing removes the PCs' games: that's the
installer .pkt's state. Its installer page (pt/dos-installer/) adds games as
g<n>.js and lists them in the page between the <!--games--> markers.

v86 comes from vendor/v86/ (npm package v86, plus bios/*.bin from its GitHub
repo), FreeDOS from dosgames/freedos/freedos722.img (https://i.copy.sh/freedos722.img),
the mouse and CD-ROM drivers from FreeDOS 1.3's packages (see TOOLS_DIR).
"""
import base64
import io
import json
import struct
import sys
import zipfile

from PIL import Image, ImageDraw, ImageFont

from paths import DIST, ROOT

V86 = ROOT / "vendor" / "v86"
OUT = DIST / "v86app"
FLOPPY = ROOT / "dosgames" / "freedos" / "freedos722.img"
OPL = ROOT / "vendor" / "opl" / "opl.wasm"   # from tools/build_opl.py
DOOM_DIR = ROOT / "dosgames" / "doom"
# From FreeDOS 1.3's packages (ctmouse, udvd2, shsucdx, devload, unpacked into
# dosgames/cdrom/): the mouse driver, loaded for every game, and for games with
# a CD the CD extensions and DEVLOAD, which loads the CD-ROM driver (UDVD2,
# FreeDOS's with CD audio functions added: tools/build_udvd2.py).
TOOLS_DIR = ROOT / "dosgames" / "cdrom" / "BIN"
TOOL_FILES = {"ctmouse": "CTMOUSE.EXE", "devload": "DEVLOAD.COM", "shsucdx": "SHSUCDX.COM"}
UDVD2 = ROOT / "vendor" / "udvd2" / "UDVD2.SYS"   # from tools/build_udvd2.py

AUTOEXEC = """@echo off
set PATH=A:\\FDOS
set BLASTER=A220 I5 D1 H5 T6
if exist C:\\PTDOS.BAT goto games
echo.
echo FreeDOS in Packet Tracer. No games installed yet.
echo.
goto end
:games
C:
call C:\\PTDOS.BAT
:end
""".replace("\n", "\r\n")

# v86's SB16: port 220, IRQ 5, DMA 1. Music: AdLib, played by the page's own
# OPL3 (v86 has no FM synthesis).
DOOM_CFG = """mouse_sensitivity 5
sfx_volume 8
music_volume 8
show_messages 1
use_mouse 0
use_joystick 0
snd_channels 8
snd_musicdevice 3
snd_sfxdevice 3
snd_sbport 544
snd_sbirq 5
snd_sbdma 1
snd_mport 816
screenblocks 10
detaillevel 0
usegamma 0
""".replace("\n", "\r\n")

# The canvas always fills the largest 4:3 box in the window, the shape DOS
# games were drawn for, with no page pointer over it (only the game's cursor); !important because v86 sets its own pixel size (and a
# scale transform) for modes such as 640x400, which then overflow the window.
# Names the page mentions. Packet Tracer rewrites every occurrence of a [gui]
# file's name in the page, so none may contain another.
PAGE = """<!doctype html>
<html><head><meta charset="utf-8">
<style>
html,body{margin:0;height:100%;background:#000;overflow:hidden}
#screen{display:flex;align-items:center;justify-content:center;height:100%}
#screen,#screen *{cursor:none!important}
#screen div{white-space:pre;font:14px monospace;line-height:14px;color:#ccc}
#screen canvas{image-rendering:pixelated;width:min(100vw,133.33vh)!important;height:min(75vw,100vh)!important;transform:none!important}
#log{position:fixed;bottom:0;left:0;margin:0;color:#8f8;font:11px monospace;background:rgba(0,0,0,.6);z-index:99}
</style></head><body>
<div id="screen"><div></div><canvas style="display:none"></canvas></div><pre id="log"></pre>
<script src="libv86.js"></script>
<script src="v86data.js"></script>
<!--games-->GAME_TAGS<!--/games-->
<script src="ptdos.js"></script>
</body></html>
"""


# What stays on the copy.sh floppy: FreeDOS itself. It also carries games,
# demos and tools (vim, nasm, ROGUE...) whose licences aren't clear, and the
# app is published in a .pkt.
KEEP = {b"KERNEL  SYS", b"COMMAND COM", b"AUTOEXECBAT", b"CONFIG  SYS", b"README     ", b"FDOS       "}


class Floppy:
    """Just enough FAT12 to edit the root directory of a boot floppy in place."""

    def __init__(self, img: bytes):
        self.img = bytearray(img)
        bps, spc, reserved, nfats, self.root_entries = struct.unpack_from("<HBHBH", img, 11)
        fat_sectors = struct.unpack_from("<H", img, 22)[0]
        self.cluster_bytes = spc * bps
        self.fats = [(reserved + k * fat_sectors) * bps for k in range(nfats)]
        self.root_off = (reserved + nfats * fat_sectors) * bps
        self.data_off = self.root_off + self.root_entries * 32

    def root(self):
        """(offset, 11-byte name) of each live root directory entry."""
        for i in range(self.root_entries):
            at = self.root_off + 32 * i
            if self.img[at] == 0:
                break
            if self.img[at] != 0xE5 and self.img[at + 11] != 0x0F:  # skip deleted and long-name parts
                yield at, bytes(self.img[at:at + 11])

    def fat_get(self, n: int) -> int:
        v = struct.unpack_from("<H", self.img, self.fats[0] + n * 3 // 2)[0]
        return v >> 4 if n & 1 else v & 0xFFF

    def fat_set(self, n: int, value: int) -> None:
        for fat in self.fats:
            at = fat + n * 3 // 2
            v = struct.unpack_from("<H", self.img, at)[0]
            v = (v & 0x000F) | (value << 4) if n & 1 else (v & 0xF000) | value
            struct.pack_into("<H", self.img, at, v)

    def chain(self, first: int):
        c = first
        while 2 <= c < 0xFF8:
            yield c
            c = self.fat_get(c)

    def free(self, first: int, is_dir: bool) -> None:
        """Free a cluster chain, and for a folder everything inside it first."""
        if is_dir:
            for c in list(self.chain(first)):
                base = self.data_off + (c - 2) * self.cluster_bytes
                for at in range(base, base + self.cluster_bytes, 32):
                    if self.img[at] in (0, 0xE5) or self.img[at] == 0x2E or self.img[at + 11] == 0x0F:
                        continue
                    sub = struct.unpack_from("<H", self.img, at + 26)[0]
                    self.free(sub, bool(self.img[at + 11] & 0x10))
        for c in list(self.chain(first)):
            self.fat_set(c, 0)

    def strip(self, keep: set) -> list:
        removed = []
        for at, name in list(self.root()):
            if name in keep or self.img[at + 11] & 0x08:  # keep the volume label
                continue
            first = struct.unpack_from("<H", self.img, at + 26)[0]
            self.free(first, bool(self.img[at + 11] & 0x10))
            self.img[at] = 0xE5
            # Its long-name entries sit just before it; orphans upset checkers.
            lfn = at - 32
            while lfn >= self.root_off and self.img[lfn + 11] == 0x0F and self.img[lfn] != 0xE5:
                self.img[lfn] = 0xE5
                lfn -= 32
            removed.append(name.decode("ascii").strip())
        return removed

    def replace(self, name11: bytes, data: bytes) -> None:
        """Replace a root file's contents; the new data must fit its first cluster."""
        for at, name in self.root():
            if name == name11:
                break
        else:
            sys.exit(f"{name11!r} not found on the floppy")
        if len(data) > self.cluster_bytes:
            sys.exit(f"new {name11!r} is {len(data)} bytes, only {self.cluster_bytes} fit")
        first = struct.unpack_from("<H", self.img, at + 26)[0]
        rest = list(self.chain(first))[1:]
        if rest:
            self.fat_set(first, 0xFFF)
            for c in rest:
                self.fat_set(c, 0)
        off = self.data_off + (first - 2) * self.cluster_bytes
        self.img[off:off + self.cluster_bytes] = data.ljust(self.cluster_bytes, b"\0")
        struct.pack_into("<I", self.img, at + 28, len(data))


def make_floppy(img: bytes) -> bytes:
    fd = Floppy(img)
    removed = fd.strip(KEEP)
    fd.replace(b"AUTOEXECBAT", AUTOEXEC.encode("ascii"))
    print(f"floppy: removed {', '.join(removed)}")
    return bytes(fd.img)


def doom_zip() -> bytes:
    for f in (DOOM_DIR / "DOOM.EXE", DOOM_DIR / "DOOM1.WAD"):
        if not f.exists():
            sys.exit(f"{f.relative_to(ROOT)} missing: unpack shareware DOOM 1.9 there (see NOTES.md)")
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        z.write(DOOM_DIR / "DOOM.EXE", "DOOM.EXE")
        z.write(DOOM_DIR / "DOOM1.WAD", "DOOM1.WAD")
        z.writestr("DEFAULT.CFG", DOOM_CFG)
    return buf.getvalue()


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


def embed(files: dict[str, bytes]) -> str:
    lines = ["window.V86DATA=window.V86DATA||{};"]
    for name, data in files.items():
        lines.append("V86DATA[%s]=\"%s\";" % (json.dumps(name), base64.b64encode(data).decode("ascii")))
    return "\n".join(lines) + "\n"


def game_script(name: str, command: str, zip_bytes: bytes) -> str:
    """One installed game, in the form pt/dos-installer/installer.html writes."""
    entry = {"name": name, "command": command, "zip": base64.b64encode(zip_bytes).decode("ascii")}
    return "window.PTDOS_GAMES=window.PTDOS_GAMES||[];PTDOS_GAMES.push(%s);\n" % json.dumps(entry)


# v86 0.5.462's CD drive is data only: no audio tracks, no PLAY AUDIO, and it
# answers READ TOC from track 1 whatever track is asked for. One patch lets the
# page answer CD commands first: self.PTDOS_ATAPI(ide, command) returns true
# when it has (web/v86-dos.js: table of contents, sub-channel, audio
# capabilities, play, pause, stop). The string is from v86's minified code.
ATAPI_PATCHES = [
    ("else{switch(a){case 0:this.buffer?",
     "else{if(!(self.PTDOS_ATAPI&&self.PTDOS_ATAPI(this,a)))switch(a){case 0:this.buffer?"),
]


def patch_v86(js: str) -> str:
    for old, new in ATAPI_PATCHES:
        if js.count(old) != 1:
            sys.exit(f"libv86.js: expected one {old[:40]!r}...: another v86 version? Check ATAPI_PATCHES")
        js = js.replace(old, new)
    return js


def empty_iso(label: str = "PTDOSCD") -> bytes:
    """An empty ISO 9660 disc: the data track of a CD made of a game's music."""
    sector, root_at, total = 2048, 20, 32

    def both16(v: int) -> bytes:
        return v.to_bytes(2, "little") + v.to_bytes(2, "big")

    def both32(v: int) -> bytes:
        return v.to_bytes(4, "little") + v.to_bytes(4, "big")

    def record(name: bytes) -> bytes:
        body = (bytes([0]) + both32(root_at) + both32(sector) + bytes([97, 9, 30, 0, 0, 0, 0])
                + bytes([2, 0, 0]) + both16(1) + bytes([len(name)]) + name)
        rec = bytes([len(body) + 1]) + body
        return rec + bytes(len(rec) & 1)

    iso = bytearray(total * sector)
    pvd = bytearray(sector)
    pvd[0:7] = b"\x01CD001\x01"
    pvd[8:40] = b" " * 32
    pvd[40:72] = label.encode("ascii").ljust(32)
    pvd[80:88] = both32(total)
    pvd[120:124] = both16(1)
    pvd[124:128] = both16(1)
    pvd[128:132] = both16(sector)
    pvd[132:140] = both32(10)
    pvd[140:144] = (18).to_bytes(4, "little")
    pvd[148:152] = (19).to_bytes(4, "big")
    pvd[156:190] = record(b"\x00")
    pvd[190:813] = b" " * 623
    for at in (813, 830, 847, 864):
        pvd[at:at + 17] = b"0" * 16 + b"\x00"
    pvd[881] = 1
    iso[16 * sector:17 * sector] = pvd
    iso[17 * sector:17 * sector + 7] = b"\xffCD001\x01"
    for at, order in ((18, "little"), (19, "big")):
        iso[at * sector:at * sector + 10] = (bytes([1, 0]) + root_at.to_bytes(4, order)
                                             + (1).to_bytes(2, order) + bytes(2))
    root = record(b"\x00") + record(b"\x01")
    iso[root_at * sector:root_at * sector + len(root)] = root
    return bytes(iso)


def write(name: str, text: str) -> None:
    (OUT / name).write_text(text, encoding="ascii", newline="\n")


def main() -> int:
    for f in (V86 / "libv86.js", V86 / "v86.wasm", V86 / "seabios.bin", V86 / "vgabios.bin", FLOPPY, OPL,
              UDVD2, *(TOOLS_DIR / name for name in TOOL_FILES.values())):
        if not f.exists():
            sys.exit(f"{f.relative_to(ROOT)} missing (see the docstring)")
    args = sys.argv[1:]
    if args not in ([], ["--no-game"]):
        sys.exit("usage: make_v86_app.py [--no-game]")
    games = [] if args else [{"file": "g1.js", "name": "DOOM", "command": "DOOM", "zip": doom_zip()}]

    OUT.mkdir(parents=True, exist_ok=True)
    tags = "".join('<script src="%s"></script>' % g["file"] for g in games)
    write("index.html", PAGE.replace("GAME_TAGS", tags))
    write("ptdos.js", (ROOT / "web" / "v86-dos.js").read_text(encoding="ascii"))
    write("libv86.js", patch_v86((V86 / "libv86.js").read_text(encoding="ascii")))
    write("v86data.js", embed({
        "bios": (V86 / "seabios.bin").read_bytes(),
        "vgabios": (V86 / "vgabios.bin").read_bytes(),
        "fda": make_floppy(FLOPPY.read_bytes()),
        "wasm": (V86 / "v86.wasm").read_bytes(),
        "opl": OPL.read_bytes(),
        **{key: (TOOLS_DIR / name).read_bytes() for key, name in TOOL_FILES.items()},
        "udvd2": UDVD2.read_bytes(),
        "cdempty": empty_iso(),
    }))
    for old in list(OUT.glob("g*.js")) + [OUT / "game.js"]:
        old.unlink(missing_ok=True)
    for g in games:
        write(g["file"], game_script(g["name"], g["command"], g["zip"]))
    write("games.json", json.dumps([{"file": g["file"], "name": g["name"]} for g in games]))
    make_icon().save(OUT / "icon.png")

    # Packet Tracer wants forward slashes, also on Windows.
    installer = (ROOT / "pt" / "install-v86-app.js").read_text(encoding="utf-8")
    (DIST / "install-v86-app.js").write_text(installer.replace("__PTDOOM_DIST__", DIST.as_posix()),
                                             encoding="utf-8", newline="\n")

    outputs = [OUT / f for f in ("index.html", "ptdos.js", "libv86.js", "v86data.js", "icon.png", "games.json")]
    outputs += [OUT / g["file"] for g in games]
    for f in outputs + [DIST / "install-v86-app.js"]:
        print(f"ok: {f.relative_to(ROOT)} ({f.stat().st_size:,} bytes)")
    if not games:
        print("no games: installing removes the PCs' games")
    return 0


if __name__ == "__main__":
    sys.exit(main())
