# PTDoom

Doom running inside Cisco Packet Tracer 9.0.1, as an app on a simulated PC's Desktop.

It works because Packet Tracer's Desktop apps and extension windows are web pages in a full Chromium (QtWebEngine 6.8.7, Chrome 130) with WebAssembly. The game is [doomgeneric](https://github.com/ozkl/doomgeneric), a portable build of Chocolate Doom, compiled to WebAssembly with Emscripten. Music plays as on a Sound Blaster: [Chocolate Doom](https://github.com/chocolate-doom/chocolate-doom)'s OPL music player and the Nuked OPL3 FM synth emulator are added from Chocolate Doom 3.0.1 (`src/music/`).

See also [PTDOS](https://github.com/unoriginalnickname/PTDOS), split off from this repo: DOS games in a Packet Tracer PC (v86 + FreeDOS).

## Play

You need Packet Tracer 9.0.1 and a DOOM game file (a WAD).

**The WAD is not included**: it's id Software's, so you bring your own. The free shareware episode's **doom1.wad** works. To get one:

- Download it from the link on Doom Wiki's [DOOM1.WAD page](https://doomwiki.org/wiki/DOOM1.WAD). The right file (v1.9) is 4,196,020 bytes, SHA-1 `5b2e249b9c5133ec987b3ea77596381dc0d6bc1d`.
- With Python: `python tools/fetch_wad.py` in a copy of this repo. It downloads doom1.wad from Debian's `doom-wad-shareware` package, checks it, and saves it as `wad/doom1.wad`.
- Or use a copy you already have: the installer also accepts `doom.wad` (for example from DOOM on Steam or GOG) and `doom2.wad` (untested).
- Or play [Freedoom](https://freedoom.github.io/) instead: a free, complete replacement for DOOM's data by volunteers, with its own art and levels. `freedoom1.wad` from its [download](https://github.com/freedoom/freedoom/releases) works (tested with v0.13.0).

1. Download [PTDoom-installer.pkt](https://github.com/unoriginalnickname/PTDoom/raw/master/PTDoom-installer.pkt) and open it in Packet Tracer.
2. Packet Tracer asks whether to allow the file's script. Allow it, and the **Install DOOM** window opens.
3. Choose your WAD.
4. Save the file under a new name (**File → Save As**): that copy has the game in it.
5. Click **DOOM-PC → Desktop → DOOM**. Click the game to give it the keyboard.

Controls: arrows move, Ctrl fires, Space opens doors, Enter/Esc for menus.

You can also type `doom` in DOOM-PC's Command Prompt: the game opens in its own window.

## How it works

A Desktop app is a project folder on the PC with an `app_manifest.xml`, a `main.py`, and page files prefixed `[gui]`. The page itself is loaded as a `data:` URL capped at 2 MB, but Packet Tracer serves the app's other `[gui]` files separately, so the engine goes in `doom.js` (1.7 MB) and the game data in `wad.js`.

The installer `.pkt` ships the engine without game data. Its File Script Module (`pt/installer/`) opens a page that reads the WAD you choose, checks it, draws the Desktop icon from Doomguy's face in it, and writes both into the app. The same module watches the PCs' Command Prompts: `doom` opens `play.html`, which reads the game from the PC's app and runs it in a window. `NOTES.md` has the details and what was learned on the way.

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

## Known issues

- Audio can glitch while loading.
- Opening an app window can disconnect packet-tracer-mcp's bridge; reopen **Extensions → MCP Bridge**.

## Licences

- doomgeneric, Chocolate Doom and Nuked OPL3 (`src/`), and so the engine in `PTDoom-installer.pkt`: GPL-2.0 or later.
- DOOM's own WADs (`doom1.wad`, `doom.wad`, `doom2.wad`): id Software's. None is included here; `tools/fetch_wad.py` downloads the shareware one.
- Freedoom's WADs: free, under a BSD licence (not included either).
