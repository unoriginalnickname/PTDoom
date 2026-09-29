# PTDoom

Doom running inside Cisco Packet Tracer 9.0.1, as an app on a simulated PC's Desktop.

It works because Packet Tracer's Desktop apps and extension windows are web pages in a full Chromium (QtWebEngine 6.8.7, Chrome 130) with WebAssembly. The game is [doomgeneric](https://github.com/ozkl/doomgeneric), a portable build of Chocolate Doom, compiled to WebAssembly with Emscripten.

## Play

You need Packet Tracer 9.0.1 and a DOOM game file (a WAD). The shareware episode's **doom1.wad** is free to share and works. The installer also accepts `doom.wad`, `doom2.wad` and Freedoom's WADs, but only doom1.wad has been tested. This repo doesn't include one.

1. Download [PTDoom-installer.pkt](PTDoom-installer.pkt) and open it in Packet Tracer.
2. Packet Tracer asks whether to allow the file's script. Allow it, and the **Install DOOM** window opens.
3. Choose your WAD.
4. Save the file under a new name (**File → Save As**): that copy has the game in it.
5. Click **DOOM-PC → Desktop → DOOM**. Click the game to give it the keyboard.

Controls: arrows move, Ctrl fires, Space opens doors, Enter/Esc for menus.

The app also adds a `doom` command to DOOM-PC's Command Prompt. It prints a banner and points to the Desktop: nothing in a Desktop app's APIs can open its own window.

## How it works

A Desktop app is a project folder on the PC with an `app_manifest.xml`, a `main.py`, and page files prefixed `[gui]`. The page itself is loaded as a `data:` URL capped at 2 MB, but Packet Tracer serves the app's other `[gui]` files separately, so the engine goes in `doom.js` (1.7 MB) and the game data in `wad.js`.

The installer `.pkt` ships the engine without game data. Its File Script Module (`pt/installer/`) opens a page that reads the WAD you choose, checks it, draws the Desktop icon from Doomguy's face in it, and writes both into the app. `NOTES.md` has the details and what was learned on the way.

## Build

For changing the engine or the installer. Needs Python with Pillow and the [Emscripten SDK](https://emscripten.org/docs/getting_started/downloads.html). No `make`.

```sh
git clone --depth 1 https://github.com/ozkl/doomgeneric.git vendor/doomgeneric
python tools/fetch_wad.py   # shareware doom1.wad from Debian's package, SHA-1 checked
python tools/build.py       # run with emcc on PATH and EM_CONFIG set
python tools/make_app.py
```

`build.py` makes `dist/engine.html`, the engine without game data. `make_app.py` makes the app's files in `dist/app/`, `dist/doom.html` (engine and WAD in one page, which also runs in an ordinary browser), and two Packet Tracer scripts in `dist/` with this repo's path filled in. Both scripts run in Packet Tracer's Script Engine, for example with [packet-tracer-mcp](https://github.com/jcorderop02/packet-tracer-mcp)'s `pt_send_raw`:

- `dist/install-app.js` installs DOOM, WAD included, on every PC and laptop on the canvas (or those listed in `DEVICES`). Running it again updates them.
- `dist/doom-command.js` makes typing `doom` in any PC's Command Prompt open the game in a separate window. It runs until Packet Tracer closes.

To remake the installer: install the app without `[gui]wad.js` and with `dist/app/icon-generic.png` as the icon, then in **Extensions → Scripting → Edit File Script Module** import `pt/installer/ptdoom.js` (Script Engine) and `pt/installer/installer.html` (Custom Interfaces), and tick Get Network Info, Change Network Info, Change User Interface and Miscellaneous UI under General → Security. Save with Packet Tracer's own **File → Save**.

## Known issues

- No music: doomgeneric's MIDI playback needs sound-bank files that aren't included. Sound effects work.
- Audio can glitch while loading.
- Opening an app window can disconnect packet-tracer-mcp's bridge; reopen **Extensions → MCP Bridge**.

## Licences

- doomgeneric / Chocolate Doom, and so the engine in `PTDoom-installer.pkt`: GPL-2.0.
- DOOM WADs: id Software's. None is included here; `tools/fetch_wad.py` downloads the shareware one.
