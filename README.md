# PTDoom

Doom running inside Cisco Packet Tracer 9.0.1. Type `doom` in a simulated PC's Command Prompt and the game opens in a Packet Tracer window.

It works because Packet Tracer's extension windows are a full Chromium (QtWebEngine 6.8.7, Chrome 130) with WebAssembly. The game is [doomgeneric](https://github.com/ozkl/doomgeneric), a portable build of Chocolate Doom, compiled to WebAssembly with Emscripten.

## Build

Needs Python and the [Emscripten SDK](https://emscripten.org/docs/getting_started/downloads.html). No `make`.

```sh
git clone --depth 1 https://github.com/ozkl/doomgeneric.git vendor/doomgeneric
python tools/fetch_wad.py   # shareware DOOM1.WAD from Debian's package, SHA-1 checked
python tools/build.py       # run with emcc on PATH and EM_CONFIG set
```

Output: `dist/doom.html`, one self-contained file (engine, wasm and WAD), about 7 MB. It also runs in an ordinary browser.

## Run in Packet Tracer

Run `pt/doom-command.js` once per Packet Tracer session in its Script Engine, for example with [packet-tracer-mcp](https://github.com/jcorderop02/packet-tracer-mcp)'s `pt_send_raw`. Then on any PC or server: **Desktop → Command Prompt**, type `doom`, press Enter. The prompt still says "Invalid Command."; the window opens anyway.

Controls: arrows move, Ctrl fires, Space opens doors, Enter/Esc for menus. Click the window first to give it the keyboard.

## Known issues

- No music: doomgeneric's MIDI playback needs sound-bank files that aren't included. Sound effects work.
- Audio can glitch while loading.
- `DOOM_URL` in `pt/doom-command.js` is an absolute path to this machine's copy.

## Licences

- doomgeneric / Chocolate Doom: GPL-2.0.
- DOOM1.WAD: id Software's shareware licence. Not included in this repo; `tools/fetch_wad.py` downloads it.
