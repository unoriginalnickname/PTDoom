# PTDoom

Doom running inside Cisco Packet Tracer 9.0.1, as an app on a simulated PC's Desktop.

It works because Packet Tracer's Desktop apps and extension windows are web pages in a full Chromium (QtWebEngine 6.8.7, Chrome 130) with WebAssembly. The game is [doomgeneric](https://github.com/ozkl/doomgeneric), a portable build of Chocolate Doom, compiled to WebAssembly with Emscripten. Music plays as on a Sound Blaster: [Chocolate Doom](https://github.com/chocolate-doom/chocolate-doom)'s OPL music player and the Nuked OPL3 FM synth emulator are added from Chocolate Doom 3.0.1 (`src/music/`).

There is also a second app, **DOS**: a whole emulated PC ([v86](https://github.com/copy/v86)) running [FreeDOS](https://www.freedos.org/), for DOS games. See [DOS games](#dos-games).

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

## DOS games

A DOS PC inside the Packet Tracer PC: v86 emulates an x86 PC with a Sound Blaster 16 and boots FreeDOS from a floppy. The games you add go on drive C:. Tested with shareware DOOM and Wolfenstein 3D 1.4, both with sound and FM music.

**No games are included.** Only use games you may copy: shareware, freeware, or your own copy of a commercial game. Each one is a `.zip` of the game's files, as it would sit on a hard disk (not an installer).

1. Download [PTDOS-installer.pkt](https://github.com/unoriginalnickname/PTDoom/raw/master/PTDOS-installer.pkt) and open it in Packet Tracer.
2. Allow the file's script. The **DOS games** window opens.
3. Under **Add a game**, choose a `.zip`. Check the **Name** (up to 8 letters: what you type to start it) and the **Program** it guessed, then **Install**. Repeat for more games.
4. Save the file under a new name (**File → Save As**).
5. Click **DOS-PC → Desktop → DOS**. Press a key once to turn the sound on. FreeDOS lists the games; type a game's name at `C:\>`.

Typing `dos` in DOS-PC's Command Prompt reopens the games window. A DOS window that is already open only sees newly added games after you close and reopen it.

The game fills the largest 4:3 area of the PC's window, so resize the window to make it bigger. A mouse driver (CuteMouse) is loaded for every game. Over the game only the game's own cursor shows; if it drifts away from where your hand is, push the mouse against a window edge to line them up again (Packet Tracer's window doesn't let the page capture the mouse).

### Dungeon Keeper

Runs from your own copy of the DOS version (tested with EA's Dungeon Keeper Gold, which runs it in DOSBox), without its CD:

1. `python tools/make_keeper_zip.py "<folder with KEEPER.EXE>"`, for example `"D:/EAGames/Dungeon Keeper/DATA"`. It writes `dosgames/keeper/keeper.zip` (about 100 MB), leaving out DOSBox, the CD image and the CD music, and points the game's `KEEPER.CFG` at `C:\KEEPER`.
2. Add that zip in the games window with Name **KEEPER** and Program **KEEPER** (both are guessed from the zip's name).
3. At `C:\>` type `keeper`. Deeper Dungeons is `deeper` in the same folder (`cd keeper`).

No music: it's CD audio, which the emulator doesn't play.

## How it works

A Desktop app is a project folder on the PC with an `app_manifest.xml`, a `main.py`, and page files prefixed `[gui]`. The page itself is loaded as a `data:` URL capped at 2 MB, but Packet Tracer serves the app's other `[gui]` files separately, so the engine goes in `doom.js` (1.7 MB) and the game data in `wad.js`.

The installer `.pkt` ships the engine without game data. Its File Script Module (`pt/installer/`) opens a page that reads the WAD you choose, checks it, draws the Desktop icon from Doomguy's face in it, and writes both into the app. The same module watches the PCs' Command Prompts: `doom` opens `play.html`, which reads the game from the PC's app and runs it in a window. `NOTES.md` has the details and what was learned on the way.

The DOS app works the same way: v86 in `[gui]libv86.js`, the BIOS, FreeDOS floppy and WebAssembly in `[gui]v86data.js`, and each game's zip in a `[gui]g<n>.js`. The page (`web/v86-dos.js`) unzips the games and builds drive C: as a FAT16 disk in memory before booting. At boot `C:\PTDOS.BAT` loads CuteMouse, and for a game that comes with a CD image also a CD-ROM driver and CD extensions, so the image is drive D: (nothing in the games window adds one yet). v86 has no FM synthesis, so the page catches the AdLib ports and plays them through Nuked OPL3 compiled to its own small WebAssembly module (`src/v86opl/`). It also times the VGA retrace like a real card, without which Wolfenstein 3D hangs on a black screen. The installer's module is `pt/dos-installer/`.

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

The DOS app needs FreeDOS 1.3's `ctmouse`, `udvd2`, `shsucdx` and `devload` packages unpacked into `dosgames/cdrom/` (from https://www.ibiblio.org/pub/micro/pc-stuff/freedos/files/repositories/1.3/, `base/` and `drivers/`), v86 in `vendor/v86/` (`libv86.js`, `v86.wasm` and `LICENSE` from the npm package `v86`, `seabios.bin` and `vgabios.bin` from its repo's `bios/`) and FreeDOS's boot floppy at `dosgames/freedos/freedos722.img` (from `https://i.copy.sh/freedos722.img`). Then:

```sh
python tools/build_opl.py         # Nuked OPL3 as vendor/opl/opl.wasm, with emcc
python tools/make_v86_app.py      # dist/v86app/ with shareware DOOM from dosgames/doom/
python tools/make_v86_app.py --no-game   # no games, for the installer
```

`dist/install-v86-app.js` installs it on every PC, like `install-app.js`. The DOS installer is remade like DOOM's (below), with the app installed from a `--no-game` build and `pt/dos-installer/ptdos.js` and `installer.html` in the module.

To remake the installer: install the app without `[gui]wad.js` and with `dist/app/icon-generic.png` as the icon, then in **Extensions → Scripting → Edit File Script Module** import `pt/installer/ptdoom.js` (Script Engine) and `pt/installer/installer.html` and `play.html` (Custom Interfaces), and under General → Security tick Get Network Info, Change Network Info, Change User Interface, Miscellaneous UI, and Allow opening file even if security privileges are not granted. Save with Packet Tracer's own **File → Save**.

## Known issues

- Audio can glitch while loading.
- Opening an app window can disconnect packet-tracer-mcp's bridge; reopen **Extensions → MCP Bridge**.

## Licences

- doomgeneric, Chocolate Doom and Nuked OPL3 (`src/`), and so the engine in `PTDoom-installer.pkt`: GPL-2.0 or later.
- `PTDOS-installer.pkt` also ships:
  - [v86](https://github.com/copy/v86) 0.5.462: BSD-2-Clause, Copyright (c) 2012, The v86 contributors. Full notice in [`licenses/v86.txt`](licenses/v86.txt).
  - [SeaBIOS](https://www.seabios.org/) and its VGA BIOS, as distributed with v86: LGPL-3.0. Source: https://github.com/coreboot/seabios.
  - FreeDOS, from the boot floppy image `freedos722.img` (v86's copy, trimmed): the FreeDOS kernel, the FreeCOM shell (`COMMAND.COM`), ATTRIB, EDIT, HIMEM and XCOPY, all GPL-2.0. Source: [kernel](https://github.com/FDOS/kernel), [FreeCOM](https://github.com/FDOS/freecom), and the other programs' packages at [ibiblio's FreeDOS archive](https://www.ibiblio.org/pub/micro/pc-stuff/freedos/files/). FreeDOS is a trademark of Jim Hall.
  - Nuked OPL3 (`src/music/opl3.c`, built by `src/v86opl/`): GPL-2.0 or later.
  - From FreeDOS 1.3's packages, loaded from drive C: at boot: CuteMouse 2.1b4 (`CTMOUSE.EXE`, GPL-2.0), DEVLOAD 3.25a (GPL-2.0), UDVD2 (Jack R. Ellis, "free with sources") and SHSUCDX 3.09 (John H. McCoy and Jason Hood, freeware). Sources: each package's `SOURCE` folder, and [ctmouse](https://gitlab.com/FreeDOS/base/ctmouse), [devload](https://gitlab.com/FreeDOS/base/devload), [udvd2](https://gitlab.com/FreeDOS/drivers/udvd2), [shsucdx](https://gitlab.com/FreeDOS/base/shsucdx).
  - v86's `libv86.js` is patched at build time (`TOC_PATCHES` in `tools/make_v86_app.py`) to answer a CD's table of contents from the track asked for.
- DOS games: none are included. Each belongs to its publisher.
- DOOM's own WADs (`doom1.wad`, `doom.wad`, `doom2.wad`): id Software's. None is included here; `tools/fetch_wad.py` downloads the shareware one.
- Freedoom's WADs: free, under a BSD licence (not included either).
