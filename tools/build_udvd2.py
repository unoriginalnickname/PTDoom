"""Build the DOS app's CD-ROM driver: vendor/udvd2/UDVD2.SYS.

src/udvd2/UDVD2.ASM is FreeDOS 1.3's UDVD2 (Jack R. Ellis; package udvd2,
https://gitlab.com/FreeDOS/drivers/udvd2) with two IOCTL functions added,
marked PTDoom: input 4, Audio Channel Info, which the Miles Sound System's CD
audio asks for before it plays anything (Dungeon Keeper's music), and output
3, Audio Control, accepted and ignored. tools/make_v86_app.py embeds the result.

Needs JWasm 2.20 in vendor/jwasm/ (JWasm_v220_win32.zip from
https://github.com/Baron-von-Riedesel/JWasm/releases). -Zm is MASM 5.1 syntax,
which the source is written in; the unchanged source rebuilds byte for byte.
"""
import subprocess
import sys

from paths import ROOT

JWASM = ROOT / "vendor" / "jwasm" / "JWasm.exe"
SRC = ROOT / "src" / "udvd2" / "UDVD2.ASM"
OUT = ROOT / "vendor" / "udvd2" / "UDVD2.SYS"


def main() -> int:
    if not JWASM.exists():
        sys.exit(f"{JWASM.relative_to(ROOT)} missing (see the docstring)")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([str(JWASM), "-Zm", "-bin", "-nologo", "-Fo", str(OUT), str(SRC)],
                   check=True, cwd=OUT.parent)
    print(f"ok: {OUT.relative_to(ROOT)} ({OUT.stat().st_size:,} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
