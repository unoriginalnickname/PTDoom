// Install DOOM as a Desktop app on Packet Tracer PCs.
//
// Run dist/install-app.js, not this file: tools/make_app.py writes it with
// the repo's path filled in. Run it in Packet Tracer's Script Engine, for
// example with packet-tracer-mcp's pt_send_raw, which takes one expression,
// hence the wrapper function. Running it again updates the installed copies.
//
// How it works: a desktop app is a project folder on the device's Dev: file
// system. Files prefixed [gui] belong to the page. The page itself is loaded
// as a data: URL capped at 2 MB, but Packet Tracer rewrites references to the
// other [gui] files into user-app: URLs with no such cap, so the 7 MB engine
// lives in [gui]doom.js. Packet Tracer keeps binary files such as the icon as
// base64 text, which is what getFileBinaryContents returns.
(function () {
  // Device names to install on; empty means every PC and laptop.
  var DEVICES = [];
  var TYPE = "Pc";  // laptops report this class too
  var APP_DIR = "__PTDOOM_DIST__/app/";

  var ID = "com.ptdoom.doom";
  var FOLDER = ID + " (Python)";
  var MANIFEST = [
    "<application>",
    "<id>" + ID + "</id>",
    "<version>1.0</version>",
    "<name>DOOM</name>",
    "<description>DOOM (doomgeneric, shareware episode).</description>",
    "<author>PTDoom</author>",
    "<gui>",
    "<name>DOOM</name>",
    "<html>index.html</html>",
    "<icon>icon.png</icon>",
    "</gui>",
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

  var sfm = ipc.systemFileManager();
  var files = {
    "app_manifest.xml": MANIFEST,
    "main.py": MAIN_PY,
    "[gui]index.html": sfm.getFileContents(APP_DIR + "index.html"),
    "[gui]doom.js": sfm.getFileContents(APP_DIR + "doom.js"),
    "[gui]icon.png": sfm.getFileBinaryContents(APP_DIR + "icon.png")
  };
  for (var f in files) {
    if (!files[f]) return "missing " + f + " in " + APP_DIR + ": run tools/make_app.py";
  }

  function install(device) {
    var root = device.getProcess("FileManager").getFileSystem("Dev:");
    // addDirectory throws "File exists" on a reinstall, and addTextFile
    // won't replace a file, so clear old copies first.
    if (!root.fileExist(FOLDER)) root.addDirectory(FOLDER, true);
    var dir = root.getFile(FOLDER);
    for (var name in files) {
      if (dir.fileExist(name)) dir.removeFile(name, true);
      dir.addTextFile(name, files[name], true);
    }
    if (!device.getUserDesktopAppById(ID)) device.addUserDesktopApp(FOLDER);
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
  return "DOOM installed on " + names.join(", ");
})()
