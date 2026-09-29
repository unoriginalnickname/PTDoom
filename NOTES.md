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
- `pt/install-app.js` collects the install steps. **Not yet run as a file**: each step was tested on its own, but not the script as a whole.
- Still to do: README section on the desktop app, push to GitHub (no remote yet), a real `doom` command via `<cli>`.
- **"Max number of apps running"**: apps with `<background>true</background>` keep running after their window closes. `device.stopProject(dir)` stops them without trouble when they're healthy. Don't mark test apps as background.
- The bridge only takes a single expression: wrap code in `(function(){ ... })()`, no top-level `return`. File text is `file.getContent(true).text`.
- **Don't use `device.runCodeInProject`.** It returned true but showed nothing, and afterwards the app froze: clicks drew nothing, probably because `main.py` was stuck. `stopProject` on that app then timed out and dropped the bridge.

Next ideas, in order:

1. Small page plus `main.js` sending `doom.txt` in chunks through `GUI.update`, the page joining them and `document.write`-ing the game. Test the file read first with a small file, not the 7 MB one.
2. Fallback: the Desktop app's page just asks for the separate URL-loaded window to open (for example through the watcher), so the icon works even if the game can't live inside the PC's window.
