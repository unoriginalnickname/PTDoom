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

Next ideas, in order:

1. Small page plus `main.js` sending `doom.txt` in chunks through `GUI.update`, the page joining them and `document.write`-ing the game. Test the file read first with a small file, not the 7 MB one.
2. Fallback: the Desktop app's page just asks for the separate URL-loaded window to open (for example through the watcher), so the icon works even if the game can't live inside the PC's window.
