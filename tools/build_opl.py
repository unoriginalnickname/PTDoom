"""Build Nuked OPL3 as a standalone wasm module for the DOS app: vendor/opl/opl.wasm.

src/v86opl/opl_wasm.c wraps src/music/opl3.c (the same emulator the native
DOOM's music uses). tools/make_v86_app.py embeds the result. Needs emsdk; see
the build notes in NOTES.md.
"""
import os
import shutil
import subprocess
import sys

from paths import ROOT

OUT = ROOT / "vendor" / "opl" / "opl.wasm"


def main() -> int:
    emcc = shutil.which("emcc") or shutil.which("emcc.bat")
    if not emcc:
        sys.exit("emcc not on PATH (see NOTES.md for the emsdk set-up)")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    cmd = [emcc, "-O3", "--no-entry", "-sSTANDALONE_WASM", "-sFILESYSTEM=0",
           "-sEXPORTED_FUNCTIONS=_opl_reset,_opl_write,_opl_render",
           "-sINITIAL_MEMORY=1MB", "-sSTACK_SIZE=64KB", "-sALLOW_MEMORY_GROWTH=0",
           str(ROOT / "src" / "v86opl" / "opl_wasm.c"), str(ROOT / "src" / "music" / "opl3.c"),
           "-o", str(OUT)]
    subprocess.run(cmd, check=True)
    print(f"ok: {OUT.relative_to(ROOT)} ({OUT.stat().st_size:,} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
