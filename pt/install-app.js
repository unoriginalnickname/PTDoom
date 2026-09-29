// Install DOOM as a Desktop app on one Packet Tracer PC.
//
// Run in Packet Tracer's Script Engine, for example with packet-tracer-mcp's
// pt_send_raw (it takes one expression, hence the wrapper function). Set
// DEVICE and APP_DIR first. Needs dist/app/ from tools/split_app.py and
// tools/make_icon.py.
//
// How it works: a desktop app is a project folder on the device's Dev: file
// system. Files prefixed [gui] belong to the page. The page itself is loaded
// as a data: URL capped at 2 MB, but Packet Tracer rewrites references to the
// other [gui] files into user-app: URLs with no such cap, so the 7 MB engine
// lives in [gui]doom.js. Packet Tracer keeps binary files such as the icon as
// base64 text, which is what getFileBinaryContents returns.
(function () {
  var DEVICE = "PC0";
  var APP_DIR = "F:/work/coding/ClaudeWork/PTDoom/dist/app/";

  var NAME = "com.ptdoom.doom (Python)";
  var MANIFEST = [
    "<application>",
    "<id>com.ptdoom.doom</id>",
    "<version>1.0</version>",
    "<name>DOOM</name>",
    "<description>DOOM (doomgeneric, shareware episode).</description>",
    "<author>PTDoom</author>",
    "<gui>",
    "<name>DOOM</name>",
    "<html>index.html</html>",
    "<icon>icon.png</icon>",
    "</gui>",
    "<auto-install>",
    "</auto-install>",
    "</application>",
    ""].join("\n");
  // Python, not JavaScript: a main.js failed with "undefined is not a
  // function"; this is the built-in MQTT Client's pattern.
  var MAIN_PY = [
    "from gui import *",
    "from time import *",
    "",
    "def main():",
    "    GUI.setup()",
    "    while True:",
    "        delay(60000)",
    "",
    "if __name__ == \"__main__\":",
    "    main()",
    ""].join("\n");

  var device = ipc.network().getDevice(DEVICE);
  if (!device) return "no device named " + DEVICE;
  var sfm = ipc.systemFileManager();
  var page = sfm.getFileContents(APP_DIR + "index.html");
  var js = sfm.getFileContents(APP_DIR + "doom.js");
  var icon = sfm.getFileBinaryContents(APP_DIR + "icon.png");
  if (!page || !js || !icon) return "missing files in " + APP_DIR;

  var root = device.getProcess("FileManager").getFileSystem("Dev:");
  root.addDirectory(NAME, true);
  var dir = root.getFile(NAME);
  // addTextFile won't replace a file, so clear old copies first.
  ["app_manifest.xml", "main.py", "[gui]index.html", "[gui]doom.js", "[gui]icon.png"].forEach(function (f) {
    if (dir.fileExist(f)) dir.removeFile(f, true);
  });
  dir.addTextFile("app_manifest.xml", MANIFEST, true);
  dir.addTextFile("main.py", MAIN_PY, true);
  dir.addTextFile("[gui]index.html", page, true);
  dir.addTextFile("[gui]doom.js", js, true);
  dir.addTextFile("[gui]icon.png", icon, true);
  if (!device.getUserDesktopAppById("com.ptdoom.doom")) device.addUserDesktopApp(NAME);
  return "installed on " + DEVICE + ": doom.js " + dir.getFile("[gui]doom.js").getSize() + " bytes";
})()
