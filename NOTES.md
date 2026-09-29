# Working notes

State on 2026-09-29, for picking the work up in a new session.

## Works

- `dist/doom.html` plays in a Packet Tracer web view opened by URL:
  `webViewManager.createWebView("DOOM","",960,640)`, then `setUrl("file:///F:/work/coding/ClaudeWork/PTDoom/dist/doom.html")`, `show()`.
- `pt/doom-command.js` watches every PC's Command Prompt output and opens that window when someone types `doom`. The prompt still says "Invalid Command.".
- The page must be plain ASCII (`-sSINGLE_FILE_BINARY_ENCODE=0` in `tools/build.py`): Packet Tracer's `systemFileManager().getFileContents` stops at the first NUL.

## Not working yet: DOOM as a PC Desktop app

Goal: a DOOM icon in a PC's Desktop tab that plays inside the PC's window, and a real `doom` command.

How desktop apps work (found by probing, Packet Tracer 9.0.1):

- A desktop app is a project folder on the device, `Dev:/<id> (JavaScript)` or `(Python)`, with `app_manifest.xml`, `[gui]`-prefixed files for the page (`[gui]index.html`, `[gui]icon.png`), and `main.js` / `main.py`.
- Manifest format: see the built-in MQTT Client (`ipc.userAppManager().getGlobalAppAt(i)`, then `getFilesDir()` on the copy installed with `device.addUserDesktopAppFromGlobal("com.cisco.mqttclient")`). `<gui>` holds `<name>`, `<html>`, `<icon>`, and `<cli><command><name>` adds a Command Prompt command.
- Create one: `root = <any app>.getFilesDir().getParent()` (that's `Dev:`), `root.addDirectory(dir, true)`, `addTextFile(name, text, true)`, then `device.addUserDesktopApp(dir)`. Remove with `device.removeUserDesktopApp(dir)` (the folder name, not the id).
- `main.js` talks to the page: page calls `guiEvent(type, args)`, `main.js` answers with `GUI.update(type, args)`, which calls the page's `update(type, args)`. File API: `FileSystem.exists/open/dir`, `file.read()`. Docs: Packet Tracer's `help/default/iot_javascript_api.htm`.

Blockers so far:

1. **The page is loaded as a `data:` URL** (`setHtml`), so it is capped at 2 MB and can't load `file://` or neighbouring files. The 7 MB page gives a white screen; an iframe to `file://` is refused.
2. **The last `main.js` failed with "TypeError: undefined is not a function"**, probably `CLI.setup()` or `Serial`, which may only exist on IoT boards. A guarded, minimal `main.js` that reports which globals exist was written but never ran.
3. **Opening a desktop app or a DOOM window seems to drop the MCP bridge**, and Packet Tracer froze with the 7 MB file inside 1B's app folder.

Session 2 findings (2026-09-29 evening):

- **Python works where `main.js` failed.** A copy of the MQTT Client pattern (`from gui import *`, `GUI.setup()` in `main()`, `while True: delay(60000)`) runs; `guiEvent` from the page reaches `main.py` and `GUI.update` gets back to the page's `update()`. No `CLI.setup()` was needed.
- **Python `open()` reads the PC's own disk, not the app folder.** `open("test.txt")` in `Dev:/<app>` fails with "File not found". The disk is `device.getProcess("FileManager").getFileSystem("c:")` (also `Desktop:` and `Dev:`); `c:` has about 1 GB free and `addTextFile(name, text, true)` writes there. But Python's `open()` still can't see it: `/test.txt`, `test.txt`, `c:/test.txt`, `c:\test.txt` and `C:\test.txt` all fail. The help file marks the Python file API "SBC only", so on a PC, `open()` is a dead end. Next test: data in an imported `.py` module (A) and in a `[gui]data.js` script (B), app `com.ptdoom.test3`.
- **Both A and B work (299-char test).** A: `import testdata` then 5 `GUI.update` chunks joined OK. B is the better one: Packet Tracer **rewrites references to `[gui]` files in the page into `user-app:{uuid}/<name>` URLs** (it even rewrote the string `data.js` inside a log message). Only the HTML is in the `data:` URL (1980 chars here); the neighbouring files load separately. So blocker 1 may be solved: put the game in `[gui]doom.js` and load it with `<script src="doom.js">`. Next: confirm a >2 MB `[gui]` file loads.
- **Confirmed: a 2.5 MB `[gui]big.js` loads in 22 ms** (app `com.ptdoom.test4`, written with `addTextFile` without trouble). The 2 MB cap only applies to the HTML page.
- **The real game installed as `com.ptdoom.doom (Python)`.** `tools/split_app.py` splits `dist/doom.html` into `dist/app/index.html` (1 KB) and `dist/app/doom.js` (7.3 MB, pure ASCII). Install reads both from disk with `ipc.systemFileManager().getFileContents` and writes them with `addTextFile` (all 7,343,005 bytes arrived, no freeze). Manifest without `<background>`; `main.py` just `GUI.setup()` plus a wait loop.
- First open: `error: Cannot read properties of null (reading 'textContent')`. The engine does `document.getElementById("mainScript").textContent` at startup. Fixed in `split_app.py` by keeping `id=mainScript` on `<script src="doom.js">`, but the new page hadn't reached Packet Tracer yet when the bridge dropped.
- **WORKS: DOOM plays inside the PC's Desktop window** after the `mainScript` fix. Icon: Doomguy's face from the WAD (`tools/make_icon.py`). Packet Tracer stores binary files as base64 text, so `addTextFile(name, getFileBinaryContents(path), true)` works; `addTextFile` won't overwrite, so `removeFile(name, true)` first.
- `pt/install-app.js` collects the install steps; tested as a whole: fresh install, reinstall, and the default "every PC and laptop" (laptops report class `Pc` too).
- Tidy-up: `tools/split_app.py` and `tools/make_icon.py` are now one `tools/make_app.py`, which also writes `dist/install-app.js` and `dist/doom-command.js` with `__PTDOOM_DIST__` replaced by the real path. Shared paths in `tools/paths.py`.
- `doom` command: `<cli><command><name>doom</name>` in the manifest plus `cliEvent` in `main.py` (prints a banner, points to the Desktop). Registered on all test PCs (`getCommandCount() == 1`). The manifest is only read at registration, so the installer unregisters and registers again; `removeUserDesktopApp` keeps the folder. No API opens a Desktop app's window, from Python or IPC.
- **"Max number of apps running"**: apps with `<background>true</background>` keep running after their window closes. `device.stopProject(dir)` stops them without trouble when they're healthy. Don't mark test apps as background.
- The bridge only takes a single expression: wrap code in `(function(){ ... })()`, no top-level `return`. File text is `file.getContent(true).text`.
- **Don't use `device.runCodeInProject`.** It returned true but showed nothing, and afterwards the app froze: clicks drew nothing, probably because `main.py` was stuck. `stopProject` on that app then timed out and dropped the bridge.

## Packet Tracer's browser (probe, 2026-09-29)

QtWebEngine 6.8.7 / Chrome 130. WebAssembly, **WebGL 1 and 2 on the real GPU** (ANGLE, Direct3D 11), Web Audio, pointer lock, fullscreen, gamepad, workers, IndexedDB, localStorage, 1 GB WebAssembly memory. **No SharedArrayBuffer** (not cross-origin isolated), so no threaded WebAssembly builds. WebGPU exists but gives no adapter. A `fetch` to a CDN from a `file://` page failed, so bundle everything locally.

## Installer .pkt (2026-09-29)

- The engine is built without the WAD (`dist/engine.html`, 1.7 MB). `web/shell.html`'s `preRun` writes `window.DOOM_WAD = {name, data: base64}` into the file system (`-sFORCE_FILESYSTEM=1`, `EXPORTED_RUNTIME_METHODS=["FS"]`); the engine finds the WAD by name.
- **Desktop apps survive saving a `.pkt`** (tested: saved, reopened from disk, files and `doom` command intact; the .pkt compresses to about 3 MB with the WAD).
- `NetworkFile.addScript` / `addScriptFile` are the old activity scripts: saved in the file but not run on open. The File Script Module (`main()` on open, `cleanUp()` on close) is edited only in **Extensions → Scripting → Edit File Script Module**.
- **Privileges tick boxes were lost when saving through the bridge** (`fileSaveAsNoPrompt`); saving with Packet Tracer's own File → Save kept them. Without them: "does not have the necessary privilege for IPC call 'network'".
- A Custom Interface opens with `webViewManager.createWebView(title, "file-sm:installer.html", w, h)`. Web views make IPC calls with `obj.ipcCallArgsAsync(name, args, callback)` (same objects as the script engine), so the page does the whole install; a 5.6 MB `addTextFile` from the page worked.
- The script engine has no `atob` (it does have `Uint8Array`); Chromium in the page does, plus canvas for the PNG icon.
- The debug window also shows `ReferenceError: EVENT_MANAGER is not defined` several times: harmless so far, probably Packet Tracer expecting its template scripts.
- `changeNoteText` made a canvas note invisible (and `setCanvasItemX/Y` didn't move it); removing and re-adding the note worked.
- Tested end to end by hand: open installer, allow, choose doom1.wad, the window reports "Installed on DOOM-PC", DOOM plays with the Doomguy icon. Freedoom 0.13.0's `freedoom1.wad` (28.8 MB, so a 38 MB `wad.js`) also installs and plays. doom.wad / doom2.wad untested.
- **`doom` opens the game from the .pkt itself**: `ptdoom.js` polls every PC's `getCommandLine().getOutput()` (like `pt/doom-command.js`) and opens `file-sm:play.html`, which reads the app's `[gui]index.html`, `doom.js` and `wad.js` through async IPC (`getContent(true).text`) and `document.write`s the page with both scripts inline. The first version hung at "loading": the page waited on a `$se("getPlayPc", callback)` answer; it now falls back after 1 s to the first PC with the game (which path works wasn't checked).
- The installer page's white emphasis text was invisible: Packet Tracer apparently draws the page on white; fixed colours.

## Music (2026-09-30)

- doomgeneric plays music as MIDI through SDL_mixer, which needs sound-bank files: silent. Chocolate Doom 3.0.1's OPL player (`i_oplmusic.c`, `midifile.c`) and its `opl/` library with the Nuked OPL3 emulator are copied into `src/music/`; instruments come from the WAD's GENMIDI lump. `src/doomgeneric/i_sound.c` (our copy; `build.py` prefers `src/doomgeneric/*.c` over the vendor file) picks `music_opl_module`.
- Glue for the older doomgeneric: `PACKED_STRUCT` in `midifile.h`, `opl_driver_ver_t` and `I_Realloc` in `ptdoom_compat.*`, `SDL_endian.h` in `midifile.c`. Every change is marked `PTDoom`.
- **First build hung at "Running..."**: `OPL_Detect` calls `OPL_Delay`, which waits for the audio callback, and a browser's single thread never runs it. Skipped under `__EMSCRIPTEN__` (the emulator is always an OPL3).
- Engine 1,734 KB → 1,761 KB. Music tested by ear in a Packet Tracer window and in the installed app.

## DOS games through js-dos (2026-09-30)

Nobody seems to have run a DOS emulator or game in Packet Tracer before (searched). Test: js-dos 8.5.0 (npm `js-dos`, copied to `vendor/js-dos/`, gitignored) in a web view opened by URL, `dist/dos-test/index.html?w=1&b=<bundle>&a=0`.

- **Runs**: no SharedArrayBuffer needed; `file://` XMLHttpRequest loads `emulators/wdosbox.js` + `.wasm`; `workerThread: true` works from `file://` too. `pathPrefix` must point at the local `emulators/` or js-dos goes to its CDN.
- **Test game**: shareware DOOM 1.9 (`doom19s.zip` from idgames, in `dosgames/`, gitignored). The zip holds id's DEICE installer; `DOOMS_19.1` + `.2` concatenated are a self-extracting PKZIP that 7-Zip opens. Its DOOM1.WAD is the same file as `wad/doom1.wad`.
- A `.jsdos` bundle is a zip with `.jsdos/dosbox.conf`; its `[autoexec]` needs `mount c .` and `c:` first, or DOSBox says "Illegal command".
- `[sdl] autolock=true` made every click in Packet Tracer re-request pointer lock (a stream of prompts). Off, and `use_mouse 0` in DOOM's `DEFAULT.CFG`.
- **Sound: js-dos's AudioWorklet player is broken here** (high-pitched, choppy, whatever the cycles). It's hard-coded (`audioWorklet:!0` in `js-dos.js`); the test copy patches it to `window.__ptAudioWorklet!==false` and `a=0` turns it off. The fallback ScriptProcessor player sounds right. Its buffer was also raised (2048 → 4096 per callback, queue 6144 → 16384, start at 6144); no audible difference.
- **Speed**: `cycles=max` starves the audio; `fixed 20000` buzzed; `fixed 15000` is clean apart from crackle on gunshots, which lower volumes (sfx 5, music 6) didn't fix. Left for later: maybe 8-bit 11 kHz effects upsampled without filtering, or the ScriptProcessor running late on the main thread.
- **Desktop app worked** (replaced by v86 below; the js-dos build, `tools/make_dos_app.py` and `web/ptdos-shim.js`, is in commit f95bf47): `dist/dosapp/`, DOS DOOM plays inside the PC's window, sounds like the file:// test, and quitting leaves DOSBox at `C:\>`.
  - Nothing is loaded by URL: `web/ptdos-shim.js` answers `fetch` and `XMLHttpRequest` for `https://ptdos.invalid/` from base64 in `window.PTDOS_FILES`. The XHR fake shadows `readyState`/`status`/`response` with own properties.
  - js-dos skips loading `emulators.js` when a `<script id="emulators-js">` exists, so the page includes it; then set `emulators.pathPrefix` yourself.
  - The Worker is made from a `fetch` of `wdosbox.js` turned into a blob URL: works from the app's `data:` page too.
  - Packet Tracer rewrites `[gui]` file names anywhere in the page, so the bundle is `bundle.jsdos` (`game.jsdos` contains `game.js`).
  - js-dos ships non-ASCII (Russian UI strings); `make_dos_app.py` escapes it to `\uXXXX`.
- **Performance ceiling**: DOSBox in WebAssembly has no dynamic core, and js-dos's faster JSPI build needs a newer Chrome than 130.

## DOS games through v86 (2026-09-30)

v86 0.5.462 (npm `v86`: `libv86.js`, `v86.wasm`; `bios/seabios.bin` and `vgabios.bin` from its GitHub repo; all in `vendor/v86/`, gitignored). FreeDOS: `https://i.copy.sh/freedos722.img` in `dosgames/freedos/`. `tools/make_v86_test.py` builds `dist/v86test/`: boots FreeDOS from the floppy, DOOM on a generated FAT16 hard disk (the script writes MBR, BPB, FATs and root directory itself; 7-Zip reads it), types `c:` and `doom` after 8 s.

- Everything in memory again: images as `{buffer: ArrayBuffer}`, the wasm through `wasm_fn`. No SharedArrayBuffer needed.
- **Packet Tracer's AudioWorklet is bad for v86 too**: crackle, and slower. `?sa=0` hides `window.AudioWorklet`, so v86 uses its fallback player (`SpeakerBufferSourceDAC`): "near perfect", sound and speed. So the fault is Packet Tracer's AudioWorklet, not js-dos's time-stretcher alone.
- **Faster than js-dos** and cleaner sound: v86 is the better base.
- **No music**: v86's SB16 accepts FM (OPL) register writes and ignores them (`fm_default_write`). DOOM's config uses music device 0; SB IRQ 5, DMA 1 (v86's defaults).
- The test's disk is 16 MB, mostly zeros, so `disk.js` is 22 MB of base64. The app builds its disk in the page instead.

**The DOS app now runs on v86** (same id `com.ptdoom.dos`, icon `C:\>_`). `tools/make_v86_app.py` writes `dist/v86app/` and `dist/install-v86-app.js` (from `pt/install-v86-app.js`, which also removes the js-dos files).

- `web/v86-dos.js` (installed as `[gui]ptdos.js`) unzips the game (`DecompressionStream("deflate-raw")`, own zip reader) and builds drive C: as FAT16 in the page: subfolders, empty folders, 8.3 names (`LONG_F~1.TXT`), at least 32 MB with 16 MB free for saves. Tested in Node with a stand-in `V86` and checked with 7-Zip.
- The floppy's `AUTOEXEC.BAT` is replaced at build time (`Floppy.replace`, FAT12, fits its one cluster): `SET BLASTER=A220 I5 D1 H5 T6` (v86's SB16) and `call C:\PTDOS.BAT`.
- **Several games** (2026-09-30): each is a `[gui]g<n>.js` doing `PTDOS_GAMES.push({name, command, zip})`, listed in the app folder's `games.json`; the page loads them from between `<!--games-->` markers in `[gui]index.html`, which the installer page rewrites. The page puts each game in `C:\<NAME>\` (a zip whose files all sit in one folder loses that folder: `stripCommonFolder`, same rule in the installer) with a `C:\<NAME>.BAT` (`cd \<NAME>`, the command, `cd \`), and `C:\PTDOS.BAT` lists them at boot. So FreeDOS boots to `C:\>` and you type a game's name. Tested with WOLF3D14 and DOOMTEST together.
- **Installer .pkt** (`pt/dos-installer/`): `ptdos.js` opens `installer.html` ("DOS games") every time the file opens, and when someone types `dos` in a PC's Command Prompt. The page lists games (Remove needs a second click: dialogs may not work) and adds a zip with a Name (8.3, reserved DOS names refused) and a Program, guessed: shallowest .exe/.com/.bat, skipping setup/install/catalog/order..., preferring one named like the zip (`wolf3d14.zip` -> `WOLF3D`, not the order catalogue `CATALOG.EXE`). `SUB\GAME` becomes `cd SUB` + `GAME`. Packet Tracer draws that window on white whatever the CSS says, so it's styled for white (white headings were invisible).
- **Wolfenstein 3D hung on a black screen** in v86: its `VL_SetScreen` (ID_VL_A.ASM), run before its timer is hooked, waits for display (bit 0 of 0x3DA clear) then four reads in a row of blanking without retrace (bit 0 set, bit 3 clear). v86 flips bit 0 on every read and shows bit 3 for one read per drawn frame, so that never happens. Found by sampling the CPU (tight loop reading 0x3DA ~10 M/s) and confirmed from id's source by a research agent; no v86 issue or fix exists, and no DOSBox build has a WebAssembly JIT (why v86 is faster). Fix: `realRetrace` in `web/v86-dos.js` times 0x3DA/0x3BA like a 70 Hz card (vertical blank for the last 5% of each frame, retrace inside it, horizontal-blank flicker otherwise). Wolfenstein reaches its title screen; DOOM still runs.
- **Testing without Packet Tracer**: drive the app page in headless Chrome with puppeteer-core (`C:/Program Files/Google/Chrome/Application/chrome.exe`, `--allow-file-access-from-files`): build a test copy of `dist/v86app` with `g<n>.js` from `make_v86_app.game_script`, boot, `emu.keyboard_send_text("wolf3d14\n")`, screenshot, read `emu.v86.cpu.instruction_pointer[0]`, wrap `io.ports[p].read8` to count port reads. The scripts lived in a session scratchpad; rewrite them into `tools/` when needed.
- **FM music works**: `src/v86opl/opl_wasm.c` wraps Nuked OPL3 (`src/music/opl3.c`) as a 16 KB standalone wasm (`tools/build_opl.py` -> `vendor/opl/opl.wasm`, no imports). The page takes over ports 0x388-0x38B, 0x220-0x223 and 0x228-0x229 through `emu.v86.cpu.io.register_write/register_read` (names survive v86's minification) after `emulator-loaded`. Started timers "expire" at once, which passes DMX's AdLib detection. Register writes are timestamped and applied at the matching sample in a ScriptProcessor callback: timing good. DOOM's config now uses music device 3 (AdLib).
- **FreeDOS floppy trimmed** for publishing: `make_floppy` in `make_v86_app.py` deletes everything in the root but KERNEL.SYS, COMMAND.COM, AUTOEXEC.BAT, CONFIG.SYS, README and FDOS\ (ATTRIB, EDIT, HIMEM, XCOPY), freeing their FAT12 chains and long-name entries (orphans made 7-Zip report "Headers Error"). Boots and runs DOOM as before. The README asks that the FreeDOS source be available: link it when publishing.
- With no games, the page boots FreeDOS without a C: drive.
- **No sound in the PC's window at first**: the AudioContext starts suspended there (autoplay rules) and v86 only resumes it on `emulator-started`. The page wraps `AudioContext` to keep its instances and resumes them on key or mouse. Fixed; the URL-loaded window never had this.

## To do

Done: `doom` command tested by hand (prints the banner; with `doom-command.js` running, the game window opens too, confirmed). Pushed to https://github.com/unoriginalnickname/PTDoom (public, no-reply author email).

1. **Rebuild `PTDOS-installer.pkt`** (the copy in the repo root is stale and uncommitted: old one-game app and module). Open it clean, run `dist/install-v86-app.js` after `make_v86_app.py --no-game` through the bridge (new engine, no games), re-import `pt/dos-installer/ptdos.js` and `installer.html` in Edit File Script Module (keep the five Security boxes), update the canvas note (games window opens on file open; type a game's name at `C:\>`; `dos` in the Command Prompt reopens the window), save with Packet Tracer's own File > Save. The user saved the first one to `C:\Users\aadam\Cisco Packet Tracer 9.0.1\saves\`; copy it into the repo.
2. README: a "DOS games" section and the licences of what `PTDOS-installer.pkt` ships (v86 BSD-2-Clause; SeaBIOS and its VGA BIOS LGPL-3.0; FreeDOS kernel, FreeCOM, ATTRIB/EDIT/HIMEM/XCOPY GPL-2.0 with source links; Nuked OPL3 GPL-2.0+). Needed before committing the .pkt. A draft of the wording was lost to a failed edit.
3. Dungeon Keeper (the user owns it?): commercial, bring your own copy; it checks for its CD, so it needs v86's `cdrom` option and an ISO; heavy (Pentium, SVGA).
4. Keys: with two keys held a third may not register. Not the keyboard (user checked), and native DOOM does the same, so it's Packet Tracer's web view, not v86. v86's key path (keyboard.js, ps2.js) looked fine. Next step if it matters: a key-tester page showing which keydown/keyup events arrive.
5. Floppy drive: insert a disk image while running (v86 `set_fda` / `eject_fda`). The user's idea; the Desktop probably has no drag and drop, so a button with a file picker, if a picker works in a PC's window.
6. Network play (the user's idea): v86's NE2000 frames -> page -> `guiEvent` -> the PC's `main.py` -> UDP over Packet Tracer's simulated network -> the other PC's `main.py` -> `GUI.update` -> its v86. DOS DOOM's IPX play would then show up in Simulation mode and stop when a cable is pulled. Unknown: whether Packet Tracer's network keeps up with DOOM's packet rate.
7. Maybe Half-Life through Xash3D (WebGL works). Check threading first: no SharedArrayBuffer.
