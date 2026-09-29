"""Make a v86 test page: FreeDOS from a floppy, shareware DOS DOOM on a hard disk.

Output, in dist/v86test/:
  index.html   the page; ?sa=0 hides AudioWorklet so v86 uses its fallback player
  libv86.js    v86 itself
  v86data.js   BIOS, VGA BIOS, FreeDOS floppy and v86.wasm, as base64
  disk.js      the hard disk (FAT16, DOOM on it), as base64

Everything is embedded, like the js-dos app, so the same files can become a
Desktop app. v86 comes from vendor/v86/ (npm package v86, plus bios/*.bin
from its GitHub repo); FreeDOS from dosgames/freedos/freedos722.img
(https://i.copy.sh/freedos722.img); DOOM from dosgames/doom/.
"""
import base64
import json
import struct
import sys

from paths import DIST, ROOT

V86 = ROOT / "vendor" / "v86"
OUT = DIST / "v86test"
FLOPPY = ROOT / "dosgames" / "freedos" / "freedos722.img"
DOOM_DIR = ROOT / "dosgames" / "doom"

# v86's SB16: port 220, IRQ 5, DMA 1. It has no FM synthesis, so no music.
DOOM_CFG = """mouse_sensitivity 5
sfx_volume 8
music_volume 8
show_messages 1
use_mouse 0
use_joystick 0
snd_channels 8
snd_musicdevice 0
snd_sfxdevice 3
snd_sbport 544
snd_sbirq 5
snd_sbdma 1
snd_mport 816
screenblocks 10
detaillevel 0
usegamma 0
"""

# Hard disk geometry: 16 heads, 63 sectors a track, partition at sector 63.
DISK_MB = 16
SECTOR = 512
HEADS, SPT = 16, 63
PART_START = SPT
SPC = 4                 # sectors per cluster
ROOT_ENTRIES = 512


def fat16_disk(files: dict[str, bytes]) -> bytes:
    """A partitioned disk with one FAT16 partition holding files in its root."""
    total = DISK_MB * 1024 * 1024 // SECTOR
    part_sectors = total - PART_START
    root_sectors = ROOT_ENTRIES * 32 // SECTOR
    clusters = part_sectors // SPC
    fat_sectors = -(-(clusters + 2) * 2 // SECTOR)
    data_start = 1 + 2 * fat_sectors + root_sectors      # relative to the partition
    clusters = (part_sectors - data_start) // SPC
    assert 4085 <= clusters < 65525, clusters

    disk = bytearray(total * SECTOR)

    # MBR: one partition, type 0x04 (FAT16 under 32 MB), LBA and CHS.
    def chs(lba):
        c, r = divmod(lba, HEADS * SPT)
        h, s = divmod(r, SPT)
        return bytes([h, ((s + 1) & 0x3F) | ((c >> 2) & 0xC0), c & 0xFF])
    entry = b"\x80" + chs(PART_START) + b"\x04" + chs(total - 1) + struct.pack("<II", PART_START, part_sectors)
    disk[446:462] = entry
    disk[510:512] = b"\x55\xAA"

    # Boot sector with the BPB. Not bootable: FreeDOS boots from the floppy.
    bs = bytearray(SECTOR)
    bs[0:3] = b"\xEB\x3C\x90"
    bs[3:11] = b"PTDOOM  "
    struct.pack_into("<HBHBHHBHHHII", bs, 11, SECTOR, SPC, 1, 2, ROOT_ENTRIES,
                     part_sectors if part_sectors < 65536 else 0, 0xF8, fat_sectors, SPT, HEADS,
                     PART_START, part_sectors if part_sectors >= 65536 else 0)
    struct.pack_into("<BBBI11s8s", bs, 36, 0x80, 0, 0x29, 0x50544F4D, b"PTDOOM     ", b"FAT16   ")
    bs[510:512] = b"\x55\xAA"
    base = PART_START * SECTOR
    disk[base:base + SECTOR] = bs

    fat = [0xFFF8, 0xFFFF] + [0] * clusters
    root = bytearray(root_sectors * SECTOR)
    next_cluster = 2
    date = ((1995 - 1980) << 9) | (2 << 5) | 1
    for i, (name, data) in enumerate(files.items()):
        stem, _, ext = name.upper().partition(".")
        n = max(1, -(-len(data) // (SPC * SECTOR)))
        first = next_cluster
        for c in range(first, first + n):
            fat[c] = c + 1
        fat[first + n - 1] = 0xFFFF
        next_cluster += n
        off = base + (data_start + (first - 2) * SPC) * SECTOR
        disk[off:off + len(data)] = data
        struct.pack_into("<8s3sB10sHHHI", root, 32 * i, stem.ljust(8).encode(), ext.ljust(3).encode(),
                         0x20, bytes(10), 0, date, first, len(data))
    fat_bytes = struct.pack("<%dH" % len(fat), *fat)
    for k in range(2):
        off = base + (1 + k * fat_sectors) * SECTOR
        disk[off:off + len(fat_bytes)] = fat_bytes
    off = base + (1 + 2 * fat_sectors) * SECTOR
    disk[off:off + len(root)] = root
    return bytes(disk)


PAGE = """<!doctype html>
<html><head><meta charset="utf-8">
<style>
html,body{margin:0;height:100%;background:#000;overflow:hidden}
#screen{display:flex;align-items:center;justify-content:center;height:100%}
#screen div{white-space:pre;font:14px monospace;line-height:14px;color:#ccc}
#screen canvas{image-rendering:pixelated;width:auto;height:100%;max-width:100%;object-fit:contain}
#log{position:fixed;bottom:0;left:0;margin:0;color:#8f8;font:11px monospace;background:rgba(0,0,0,.6);z-index:99}
</style></head><body>
<div id="screen"><div></div><canvas style="display:none"></canvas></div><pre id="log"></pre>
<script>
var logEl=document.getElementById("log");
function log(m){logEl.textContent+=m+"\\n";}
window.onerror=function(m,s,l){log("error: "+m+" ("+l+")");};
window.addEventListener("unhandledrejection",function(e){log("error: "+(e.reason&&e.reason.message||e.reason));});
if(/[?&]sa=0/.test(location.search)){try{delete window.AudioWorklet;window.AudioWorklet=undefined;}catch(e){}}
</script>
<script src="libv86.js"></script>
<script src="v86data.js"></script>
<script src="disk.js"></script>
<script>
(function(){
  function buf(name){var b=atob(V86DATA[name]),u=new Uint8Array(b.length);for(var i=0;i<b.length;i++)u[i]=b.charCodeAt(i);delete V86DATA[name];return u.buffer;}
  var wasm=buf("wasm");
  var emu=new V86({
    wasm_fn:function(imports){return WebAssembly.instantiate(wasm,imports).then(function(r){return r.instance.exports;});},
    memory_size:32*1024*1024,vga_memory_size:2*1024*1024,
    screen_container:document.getElementById("screen"),
    bios:{buffer:buf("bios")},vga_bios:{buffer:buf("vgabios")},
    fda:{buffer:buf("fda")},hda:{buffer:buf("hda")},
    boot_order:0x321,autostart:true
  });
  var t0=performance.now();
  emu.add_listener("emulator-ready",function(){log("v86 ready, AudioWorklet "+(!!window.AudioWorklet));});
  // FreeDOS's floppy asks nothing, but give it time to reach the prompt.
  setTimeout(function(){emu.keyboard_send_text("c:\\ndoom\\n");log("typed: c: doom");},8000);
  setInterval(function(){var s=emu.get_instruction_counter?emu.get_instruction_counter():0;},1000);
  var last=0,lastT=performance.now();
  setInterval(function(){
    var n=emu.get_instruction_counter(),t=performance.now();
    document.title="v86 "+((n-last)/(t-lastT)/1000).toFixed(1)+" MIPS";
    logEl.dataset.mips=document.title;last=n;lastT=t;
  },2000);
  document.addEventListener("keydown",function(e){if(e.key==="F12")log(document.title);});
  window.emu=emu;
})();
</script>
</body></html>
"""


def b64(data: bytes) -> str:
    return base64.b64encode(data).decode("ascii")


def main() -> int:
    for f in [V86 / "libv86.js", V86 / "v86.wasm", V86 / "seabios.bin", V86 / "vgabios.bin",
              FLOPPY, DOOM_DIR / "DOOM.EXE", DOOM_DIR / "DOOM1.WAD"]:
        if not f.exists():
            sys.exit(f"{f.relative_to(ROOT)} missing (see the docstring)")
    OUT.mkdir(parents=True, exist_ok=True)
    disk = fat16_disk({
        "DOOM.EXE": (DOOM_DIR / "DOOM.EXE").read_bytes(),
        "DOOM1.WAD": (DOOM_DIR / "DOOM1.WAD").read_bytes(),
        "DEFAULT.CFG": DOOM_CFG.encode("ascii"),
    })
    data = {"bios": (V86 / "seabios.bin").read_bytes(), "vgabios": (V86 / "vgabios.bin").read_bytes(),
            "fda": FLOPPY.read_bytes(), "wasm": (V86 / "v86.wasm").read_bytes()}
    lines = ["window.V86DATA=window.V86DATA||{};"] + ["V86DATA[%s]=\"%s\";" % (json.dumps(k), b64(v)) for k, v in data.items()]
    (OUT / "v86data.js").write_text("\n".join(lines) + "\n", encoding="ascii", newline="\n")
    (OUT / "disk.js").write_text("window.V86DATA=window.V86DATA||{};V86DATA[\"hda\"]=\"%s\";\n" % b64(disk), encoding="ascii", newline="\n")
    (OUT / "libv86.js").write_bytes((V86 / "libv86.js").read_bytes())
    (OUT / "index.html").write_text(PAGE, encoding="ascii", newline="\n")
    (OUT / "disk.img").write_bytes(disk)  # for checking with other tools
    for f in ("index.html", "libv86.js", "v86data.js", "disk.js"):
        print(f"ok: {(OUT / f).relative_to(ROOT)} ({(OUT / f).stat().st_size:,} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
