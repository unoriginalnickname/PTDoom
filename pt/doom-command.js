// Adds a `doom` command to every PC and server Command Prompt in Packet Tracer.
//
// Run once per Packet Tracer session in its Script Engine (for example through
// packet-tracer-mcp's pt_send_raw). Every 500 ms it counts the `doom` commands
// in each PC's console output; when the count goes up, it opens dist/doom.html
// in a Packet Tracer web view, or brings the open one to the front. The prompt
// still answers "Invalid Command.", since the PC itself doesn't know the
// command.
//
// Counting the whole output, rather than looking at what's new, matters: the
// console can print "C:\>doom" and the newline in separate chunks.
//
// Quitting from the game's menu sends the page to about:blank#doom-exited
// (see web/shell.html); the watcher sees that URL and closes the window.
//
// Run dist/doom-command.js, not this file: tools/make_app.py writes it with
// the repo's path filled in.
(function () {
  var DOOM_URL = "file:///__PTDOOM_DIST__/doom.html";
  var g = (function () { return this; })();
  if (g.__ptDoomTimer) clearInterval(g.__ptDoomTimer);
  g.__ptDoomSeen = {};

  function count(s) {
    var m = s.match(/>[ \t]*doom[ \t]*[\r\n]/gi);
    return m ? m.length : 0;
  }

  function openWindow() {
    var w = g.__ptDoomWin ? webViewManager.getWebView(g.__ptDoomWin) : null;
    if (!w) {
      w = webViewManager.createWebView("DOOM", "", 960, 640);
      w.setCanClose(true);
      w.setUrl(DOOM_URL);
      g.__ptDoomWin = w.getWebViewId();
    }
    w.show();
    w.raise();
  }

  function closeIfQuit() {
    if (!g.__ptDoomWin) return;
    var w = webViewManager.getWebView(g.__ptDoomWin);
    if (!w) { g.__ptDoomWin = null; return; }
    if (String(w.getUrl()).indexOf("doom-exited") !== -1) {
      webViewManager.closeWebView(g.__ptDoomWin);
      g.__ptDoomWin = null;
    }
  }

  function tick() {
    closeIfQuit();
    var net = ipc.network();
    for (var i = 0; i < net.getDeviceCount(); i++) {
      var d = net.getDeviceAt(i);
      var cls = "";
      try { cls = d.getClassName(); } catch (e) {}
      if (cls !== "Pc" && cls !== "Server") continue;
      var cl = null;
      try { cl = d.getCommandLine(); } catch (e) {}
      if (!cl) continue;
      var name = d.getName();
      var c = count(String(cl.getOutput()));
      var prev = g.__ptDoomSeen[name];
      g.__ptDoomSeen[name] = c;
      if (prev !== undefined && c > prev) openWindow();
    }
  }

  tick();
  g.__ptDoomTimer = setInterval(function () { try { tick(); } catch (e) {} }, 500);
  return "doom command on: " + JSON.stringify(g.__ptDoomSeen);
})()
