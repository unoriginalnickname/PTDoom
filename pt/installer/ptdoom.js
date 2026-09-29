// PTDoom: the File Script Module of PTDoom-installer.pkt.
//
// Packet Tracer runs main() when the file opens. If no PC has the game data
// yet, it opens installer.html (a Custom Interface of this module), which
// does the installing. It also watches every PC's Command Prompt: typing
// `doom` opens play.html, which runs the game from that PC's DOOM app.
var ID = "com.ptdoom.doom";
var FOLDER = ID + " (Python)";
var installerId = null;
var playId = null;
var watchTimer = null;
var seen = {};     // device name -> number of `doom` commands in its output
var playPc = "";   // the PC play.html should load the game from

function main() {
  if (!wadInstalled()) {
    var win = webViewManager.createWebView("Install DOOM", "file-sm:installer.html", 640, 420);
    win.setCanClose(true);
    win.show();
    installerId = win.getWebViewId();
  }
  watch();
  watchTimer = setInterval(function () { try { watch(); } catch (e) {} }, 500);
}

function cleanUp() {
  if (watchTimer) clearInterval(watchTimer);
  watchTimer = null;
  [installerId, playId].forEach(function (id) {
    if (id && webViewManager.getWebView(id)) webViewManager.closeWebView(id);
  });
  installerId = playId = null;
}

function appDir(dev) {
  if (!dev.getUserDesktopAppById(ID)) return null;
  return dev.getProcess("FileManager").getFileSystem("Dev:").getFile(FOLDER);
}

function wadInstalled() {
  var net = ipc.network();
  for (var i = 0; i < net.getDeviceCount(); i++) {
    var dir = appDir(net.getDeviceAt(i));
    if (dir && dir.fileExist("[gui]wad.js")) return true;
  }
  return false;
}

// Count `doom` commands in the whole console output rather than looking at
// what's new: the prompt can print "C:\>doom" and the newline separately.
function countDoom(text) {
  var m = String(text).match(/>[ \t]*doom[ \t]*[\r\n]/gi);
  return m ? m.length : 0;
}

function watch() {
  var net = ipc.network();
  for (var i = 0; i < net.getDeviceCount(); i++) {
    var dev = net.getDeviceAt(i);
    var dir = appDir(dev);
    if (!dir || !dir.fileExist("[gui]wad.js")) continue;
    var name = dev.getName();
    var n = countDoom(dev.getCommandLine().getOutput());
    var before = seen[name];
    seen[name] = n;
    if (before !== undefined && n > before) play(name);
  }
}

function play(pcName) {
  playPc = pcName;
  var win = playId ? webViewManager.getWebView(playId) : null;
  if (win) {
    win.show();
    win.raise();
    return;
  }
  win = webViewManager.createWebView("DOOM", "file-sm:play.html", 960, 640);
  win.setCanClose(true);
  win.show();
  playId = win.getWebViewId();
}

// Called by play.html through $se().
function getPlayPc(callback) {
  $wvca(webViewManager.getWebView(playId), callback, playPc);
}
