// PTDoom: the File Script Module of PTDOS-installer.pkt.
//
// Packet Tracer runs main() when the file opens, and it opens installer.html
// (a Custom Interface of this module): the games window, which adds and
// removes games. Every time, so there's always a way to add more; typing
// `dos` in a PC's Command Prompt opens it again (the app's main.py only
// prints; watched here, like the DOOM installer's `doom`). Its "Play in a
// window" button opens play.html, the DOS app in a window of its own.
var ID = "com.ptdoom.dos";
var FOLDER = ID + " (Python)";
var installerId = null;
var watchTimer = null;
var seen = {};     // device name -> number of `dos` commands in its output

function main() {
  openGames();
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

function openGames() {
  var win = installerId ? webViewManager.getWebView(installerId) : null;
  if (win) {
    win.show();
    win.raise();
    return;
  }
  win = webViewManager.createWebView("DOS games", "file-sm:installer.html", 680, 560);
  win.setCanClose(true);
  win.show();
  installerId = win.getWebViewId();
}

// The play window (play.html): the DOS app outside a PC's Desktop, where the
// page may lock the mouse. Called by installer.html through $se().
var playId = null;
function openPlay() {
  var win = playId ? webViewManager.getWebView(playId) : null;
  if (win) {
    win.show();
    win.raise();
    return;
  }
  win = webViewManager.createWebView("DOS", "file-sm:play.html", 1024, 768);
  win.setCanClose(true);
  win.show();
  playId = win.getWebViewId();
}

function appDir(dev) {
  if (!dev.getUserDesktopAppById(ID)) return null;
  return dev.getProcess("FileManager").getFileSystem("Dev:").getFile(FOLDER);
}

// Count `dos` commands in the whole console output rather than looking at
// what's new: the prompt can print "C:\>dos" and the newline separately.
function countDos(text) {
  var m = String(text).match(/>[ \t]*dos[ \t]*[\r\n]/gi);
  return m ? m.length : 0;
}

function watch() {
  var net = ipc.network();
  for (var i = 0; i < net.getDeviceCount(); i++) {
    var dev = net.getDeviceAt(i);
    if (!appDir(dev)) continue;
    var name = dev.getName();
    var n = countDos(dev.getCommandLine().getOutput());
    var before = seen[name];
    seen[name] = n;
    if (before !== undefined && n > before) openGames();
  }
}
