# PTDoom

Doom running inside Cisco Packet Tracer 9.0.1, as an app on a simulated PC's Desktop, or in its own window from the PC's Command Prompt.

It works because Packet Tracer's extension windows are a full Chromium (QtWebEngine 6.8.7, Chrome 130) with WebAssembly. The game is [doomgeneric](https://github.com/ozkl/doomgeneric), a portable build of Chocolate Doom, compiled to WebAssembly with Emscripten.

## Build

Needs Python and the [Emscripten SDK](https://emscripten.org/docs/getting_started/downloads.html). No `make`.

```sh
git clone --depth 1 https://github.com/ozkl/doomgeneric.git vendor/doomgeneric
python tools/fetch_wad.py   # shareware DOOM1.WAD from Debian's package, SHA-1 checked
python tools/build.py       # run with emcc on PATH and EM_CONFIG set
python tools/make_app.py    # needs Pillow (pip install pillow)
```

`build.py` makes `dist/doom.html`, one self-contained file (engine, wasm and WAD), about 7 MB. It also runs in an ordinary browser.

`make_app.py` splits that into the Desktop app's files in `dist/app/`, makes its icon (Doomguy's face, from the WAD), and writes the two Packet Tracer scripts below into `dist/` with this repo's path filled in.

Both scripts run in Packet Tracer's Script Engine, for example with [packet-tracer-mcp](https://github.com/jcorderop02/packet-tracer-mcp)'s `pt_send_raw`.

## Run in Packet Tracer

### As a Desktop app

Run `dist/install-app.js`. It installs DOOM on every PC and laptop on the canvas; list names in `DEVICES` at its top to pick some. Then open a PC: **Desktop → DOOM**. Running it again updates the installed copies.

A desktop app's page is loaded as a `data:` URL capped at 2 MB, but Packet Tracer serves the app's other `[gui]` files separately, so the 7 MB engine goes in its own `doom.js`. `NOTES.md` has the details.

### From the Command Prompt

The app also adds a `doom` command to the PC's Command Prompt. It prints a banner and points to the Desktop, since nothing in a Desktop app's APIs can open its own window.

To have `doom` open the game too, run `dist/doom-command.js` once per Packet Tracer session. It watches every PC's and server's Command Prompt and opens the game in a separate Packet Tracer window. On a PC without the app, the prompt answers "Invalid Command." but the window still opens.

Controls: arrows move, Ctrl fires, Space opens doors, Enter/Esc for menus. Click the window first to give it the keyboard.

## Known issues

- No music: doomgeneric's MIDI playback needs sound-bank files that aren't included. Sound effects work.
- Audio can glitch while loading.
- The installed app reads nothing from disk afterwards, but installing needs the repo on the same machine as Packet Tracer.
- Opening an app window can disconnect packet-tracer-mcp's bridge; reopen **Extensions → MCP Bridge**.
- Not yet tested: whether the app survives saving and reopening a `.pkt`.

## Licences

- doomgeneric / Chocolate Doom: GPL-2.0.
- DOOM1.WAD: id Software's shareware licence. Not included in this repo; `tools/fetch_wad.py` downloads it.
