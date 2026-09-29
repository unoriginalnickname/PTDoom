// Install the DOS app (v86 and FreeDOS) as a Desktop app on Packet Tracer PCs.
//
// Run dist/install-v86-app.js, not this file: tools/make_v86_app.py writes it with
// the repo's path filled in. Run it in Packet Tracer's Script Engine, for
// example with packet-tracer-mcp's pt_send_raw, which takes one expression,
// hence the wrapper function. Running it again updates the installed copies.
//
// How it works: a desktop app is a project folder on the device's Dev: file
// system. Files prefixed [gui] belong to the page. The page itself is loaded
// as a data: URL capped at 2 MB, but Packet Tracer rewrites references to the
// other [gui] files into user-app: URLs with no such cap, so v86 lives in
// [gui]libv86.js, its data in [gui]v86data.js and each game in [gui]g<n>.js,
// listed in games.json (see tools/make_v86_app.py). Packet Tracer keeps
// binary files such as the icon as base64 text, which is what
// getFileBinaryContents returns.
(function () {
  // Device names to install on; empty means every PC and laptop.
  var DEVICES = [];
  var TYPE = "Pc";  // laptops report this class too
  var APP_DIR = "__PTDOOM_DIST__/v86app/";

  var ID = "com.ptdoom.dos";
  var FOLDER = ID + " (Python)";
  var MANIFEST = [
    "<application>",
    "<id>" + ID + "</id>",
    "<version>1.0</version>",
    "<name>DOS</name>",
    "<description>DOS games in FreeDOS in v86.</description>",
    "<author>PTDoom</author>",
    "<gui>",
    "<name>DOS</name>",
    "<html>index.html</html>",
    "<icon>icon.png</icon>",
    "</gui>",
    "<cli>",
    "<command>",
    "<name>dos</name>",
    "<description>Add or remove DOS games.</description>",
    "</command>",
    "</cli>",
    "</application>",
    ""].join("\n");
  // Python, not JavaScript: a main.js failed with "undefined is not a
  // function"; this is the built-in MQTT Client's pattern. Nothing in the
  // app's APIs opens its own window, so the `dos` command only prints; the
  // games window comes from the installer .pkt's script, which watches for it.
  var MAIN_PY = [
    "from gui import *",
    "from cli import *",
    "from time import *",
    "",
    "def cliEvent(type, args):",
    "    if type == \"invoked\":",
    "        print(\"Opening the DOS games window (add or remove games).\")",
    "        print(\"Play them from Desktop > DOS: type a game's name at C:\\\\>.\")",
    "        CLI.exit()",
    "",
    "def main():",
    "    GUI.setup()",
    "    CLI.setup()",
    "    while True:",
    "        delay(60000)",
    "",
    "if __name__ == \"__main__\":",
    "    main()",
    ""].join("\n");

  var sfm = ipc.systemFileManager();
  var files = {
    "app_manifest.xml": MANIFEST,
    "main.py": MAIN_PY,
    "[gui]index.html": sfm.getFileContents(APP_DIR + "index.html"),
    "[gui]ptdos.js": sfm.getFileContents(APP_DIR + "ptdos.js"),
    "[gui]libv86.js": sfm.getFileContents(APP_DIR + "libv86.js"),
    "[gui]v86data.js": sfm.getFileContents(APP_DIR + "v86data.js"),
    "[gui]icon.png": sfm.getFileBinaryContents(APP_DIR + "icon.png")
  };
  for (var f in files) {
    if (!files[f]) return "missing " + f + " in " + APP_DIR + ": run tools/make_v86_app.py";
  }
  // The games: games.json lists them (none after make_v86_app.py --no-game,
  // for the installer .pkt), and each is a [gui]g<n>.js. The PCs' old games
  // are replaced by these.
  var list = sfm.getFileContents(APP_DIR + "games.json");
  if (!list) return "missing games.json in " + APP_DIR + ": run tools/make_v86_app.py";
  files["games.json"] = list;
  var games = JSON.parse(list);
  for (var g = 0; g < games.length; g++) {
    files["[gui]" + games[g].file] = sfm.getFileContents(APP_DIR + games[g].file);
    if (!files["[gui]" + games[g].file]) return "missing " + games[g].file + " in " + APP_DIR;
  }

  // The js-dos version's files, the one-game version's, and any games.
  var OLD = ["[gui]jsdos.js", "[gui]emulators.js", "[gui]game.js"];
  for (var n = 1; n <= 99; n++) OLD.push("[gui]g" + n + ".js");

  function install(device) {
    var root = device.getProcess("FileManager").getFileSystem("Dev:");
    // addDirectory throws "File exists" on a reinstall, and addTextFile
    // won't replace a file, so clear old copies first.
    if (!root.fileExist(FOLDER)) root.addDirectory(FOLDER, true);
    var dir = root.getFile(FOLDER);
    for (var o = 0; o < OLD.length; o++) {
      if (dir.fileExist(OLD[o])) dir.removeFile(OLD[o], true);
    }
    for (var name in files) {
      if (dir.fileExist(name)) dir.removeFile(name, true);
      dir.addTextFile(name, files[name], true);
    }
    // The manifest is read when the app is registered, so register afresh:
    // otherwise a reinstall keeps the old Command Prompt commands.
    // Unregistering leaves the folder alone.
    if (device.getUserDesktopAppById(ID)) device.removeUserDesktopApp(FOLDER);
    device.addUserDesktopApp(FOLDER);
  }

  var net = ipc.network();
  var targets = [];
  if (DEVICES.length) {
    for (var i = 0; i < DEVICES.length; i++) {
      var d = net.getDevice(DEVICES[i]);
      if (!d) return "no device named " + DEVICES[i];
      targets.push(d);
    }
  } else {
    for (var j = 0; j < net.getDeviceCount(); j++) {
      var dev = net.getDeviceAt(j);
      if (dev.getClassName() === TYPE) targets.push(dev);
    }
  }
  if (!targets.length) return "no PCs or laptops on the canvas";
  var names = [];
  for (var k = 0; k < targets.length; k++) {
    install(targets[k]);
    names.push(targets[k].getName());
  }
  return "DOS installed on " + names.join(", ");
})()
