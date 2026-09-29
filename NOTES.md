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

## To do

Done: `doom` command tested by hand (prints the banner; with `doom-command.js` running, the game window opens too, confirmed). Pushed to https://github.com/unoriginalnickname/PTDoom (public, no-reply author email).

1. Other games: a DOS emulator in the browser (js-dos / em-dosbox) for old DOS games, then maybe Half-Life through Xash3D (WebGL works). Check threading first: no SharedArrayBuffer.
