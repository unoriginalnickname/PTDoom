// PTDoom installer: the File Script Module of PTDoom-installer.pkt.
//
// Packet Tracer runs main() when the file opens. If no PC has the game data
// yet, it opens installer.html (a Custom Interface of this module), which
// does the installing. Once installed and saved, the file opens quietly.
var ID = "com.ptdoom.doom";
var FOLDER = ID + " (Python)";
var installerId = null;

function main() {
  if (wadInstalled()) return;
  var win = webViewManager.createWebView("Install DOOM", "file-sm:installer.html", 640, 420);
  win.setCanClose(true);
  win.show();
  installerId = win.getWebViewId();
}

function cleanUp() {
  if (installerId && webViewManager.getWebView(installerId)) webViewManager.closeWebView(installerId);
  installerId = null;
}

function wadInstalled() {
  var net = ipc.network();
  for (var i = 0; i < net.getDeviceCount(); i++) {
    var dev = net.getDeviceAt(i);
    if (!dev.getUserDesktopAppById(ID)) continue;
    var dir = dev.getProcess("FileManager").getFileSystem("Dev:").getFile(FOLDER);
    if (dir && dir.fileExist("[gui]wad.js")) return true;
  }
  return false;
}
