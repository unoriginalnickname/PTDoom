"""Build doomgeneric for the browser with Emscripten, no make needed.

Output: dist/doom.html, one self-contained file (engine, wasm and WAD
embedded), so Packet Tracer's web view can load it from disk with setUrl.

Run from an Emscripten environment (emsdk_env), after tools/fetch_wad.py.
"""
import shutil
import subprocess
import sys

from paths import DOOM_HTML as OUT, ROOT, WAD

SRC = ROOT / "vendor" / "doomgeneric" / "doomgeneric"
OBJ = ROOT / "build"

# Same list as doomgeneric's Makefile.emscripten.
SOURCES = """dummy am_map doomdef doomstat dstrings d_event d_items d_iwad d_loop
d_main d_mode d_net f_finale f_wipe g_game hu_lib hu_stuff info i_cdmus i_endoom
i_joystick i_scale i_sound i_system i_timer memio m_argv m_bbox m_cheat m_config
m_controls m_fixed m_menu m_misc m_random p_ceilng p_doors p_enemy p_floor
p_inter p_lights p_map p_maputl p_mobj p_plats p_pspr p_saveg p_setup p_sight
p_spec p_switch p_telept p_tick p_user r_bsp r_data r_draw r_main r_plane r_segs
r_sky r_things sha1 sounds statdump st_lib st_stuff s_sound tables v_video
wi_stuff w_checksum w_file w_main w_wad z_zone w_file_stdc i_input i_video
doomgeneric doomgeneric_emscripten mus2mid i_sdlmusic i_sdlsound""".split()

CFLAGS = ["-O2", "-DFEATURE_SOUND", "-sUSE_SDL=2", "-sUSE_SDL_MIXER=2",
          "-Wno-everything"]
LDFLAGS = ["-sALLOW_MEMORY_GROWTH=1", "-sSINGLE_FILE=1", "-sEXIT_RUNTIME=1",
           # base64, not raw bytes: Packet Tracer's file reader stops at the
           # first NUL, so the page must be plain ASCII to copy onto a PC.
           "-sSINGLE_FILE_BINARY_ENCODE=0",
           "-sSDL2_MIXER_FORMATS=[\"mid\"]",
           f"--embed-file={WAD}@doom1.wad",
           f"--shell-file={ROOT / 'web' / 'shell.html'}"]


def emcc() -> str:
    exe = shutil.which("emcc") or shutil.which("emcc.bat")
    if not exe:
        sys.exit("emcc not found: run emsdk_env first")
    return exe


def main() -> int:
    if not WAD.exists():
        sys.exit("wad/doom1.wad missing: run tools/fetch_wad.py first")
    cc = emcc()
    OBJ.mkdir(exist_ok=True)
    OUT.parent.mkdir(exist_ok=True)
    objs = []
    for name in SOURCES:
        src, obj = SRC / f"{name}.c", OBJ / f"{name}.o"
        objs.append(str(obj))
        if obj.exists() and obj.stat().st_mtime > src.stat().st_mtime:
            continue
        print(f"compiling {name}.c")
        subprocess.run([cc, *CFLAGS, "-c", str(src), "-o", str(obj)], check=True)
    print(f"linking {OUT}")
    subprocess.run([cc, *CFLAGS, *LDFLAGS, *objs, "-o", str(OUT)], check=True)
    print(f"ok: {OUT} ({OUT.stat().st_size // 1024} KB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
