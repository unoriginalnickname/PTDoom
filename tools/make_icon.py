"""Make the Desktop icon: Doomguy's status-bar face, taken from the WAD.

Output: dist/app/icon.png, 100x100. Packet Tracer keeps a desktop app's
icon as base64 text in the app folder, so install it with addTextFile.

Run after tools/fetch_wad.py.
"""
import pathlib
import struct
import sys

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
WAD = ROOT / "wad" / "doom1.wad"
OUT = ROOT / "dist" / "app" / "icon.png"
FACE = "STFST01"  # looking straight ahead, full health
SIZE, SCALE = 100, 3  # same size as the built-in MQTT Client icon


def lumps(data: bytes) -> dict:
    count, offset = struct.unpack_from("<ii", data, 4)
    out = {}
    for i in range(count):
        pos, size, name = struct.unpack_from("<ii8s", data, offset + 16 * i)
        out[name.rstrip(b"\0").decode()] = data[pos:pos + size]
    return out


def decode_patch(patch: bytes, palette: bytes) -> Image.Image:
    """Doom picture format: columns of posts, index 255 in topdelta ends a column."""
    width, height = struct.unpack_from("<hh", patch, 0)
    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    px = img.load()
    for x in range(width):
        pos = struct.unpack_from("<i", patch, 8 + 4 * x)[0]
        while patch[pos] != 255:
            top, length = patch[pos], patch[pos + 1]
            for i in range(length):
                c = patch[pos + 3 + i] * 3
                px[x, top + i] = (*palette[c:c + 3], 255)
            pos += length + 4
    return img


def main() -> int:
    if not WAD.exists():
        sys.exit("wad/doom1.wad missing: run tools/fetch_wad.py first")
    wad = lumps(WAD.read_bytes())
    face = decode_patch(wad[FACE], wad["PLAYPAL"][:768])
    face = face.resize((face.width * SCALE, face.height * SCALE), Image.NEAREST)
    icon = Image.new("RGBA", (SIZE, SIZE), (40, 8, 8, 255))
    icon.alpha_composite(face, ((SIZE - face.width) // 2, (SIZE - face.height) // 2))
    OUT.parent.mkdir(parents=True, exist_ok=True)
    icon.save(OUT)
    print(f"ok: {OUT} ({OUT.stat().st_size} bytes, face {face.width}x{face.height})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
