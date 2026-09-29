// Serves js-dos's downloads from memory.
//
// A Desktop app's page is a data: URL, and its [gui] files are only reachable
// through the URLs Packet Tracer writes into the page's HTML, not through
// paths js-dos builds at runtime. So every file js-dos wants (the emulator's
// .js and .wasm, the game bundle) is embedded as base64 in window.PTDOS_FILES,
// and js-dos is pointed at a made-up prefix that fetch and XMLHttpRequest
// answer from there.
(function () {
  var PREFIX = "https://ptdos.invalid/";
  window.PTDOS_PREFIX = PREFIX;
  window.PTDOS_FILES = window.PTDOS_FILES || {};
  var cache = {};

  function nameOf(url) {
    url = String(url);
    if (url.indexOf(PREFIX) !== 0) return null;
    return url.slice(PREFIX.length).split("?")[0];
  }

  function bytes(name) {
    if (cache[name]) return cache[name];
    var b64 = window.PTDOS_FILES[name];
    if (b64 === undefined) return null;
    var bin = atob(b64), out = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    delete window.PTDOS_FILES[name];  // keep one copy, not two
    cache[name] = out;
    return out;
  }

  function type(name) {
    if (/\.js$/.test(name)) return "text/javascript";
    if (/\.wasm$/.test(name)) return "application/wasm";
    return "application/octet-stream";
  }

  var realFetch = window.fetch;
  window.fetch = function (input, init) {
    var name = nameOf(typeof input === "string" ? input : input && input.url);
    if (name === null) return realFetch.apply(this, arguments);
    var b = bytes(name);
    if (!b) return Promise.resolve(new Response("", { status: 404, statusText: "not embedded: " + name }));
    return Promise.resolve(new Response(b, {
      status: 200,
      headers: { "Content-Type": type(name), "Content-Length": String(b.length) }
    }));
  };

  // emulators.js loads the .wasm and .js with XMLHttpRequest. Its state
  // properties are read-only accessors on the prototype, so a faked request
  // shadows them with own properties.
  var P = XMLHttpRequest.prototype, open = P.open, send = P.send;
  P.open = function (method, url) {
    var name = nameOf(url);
    if (name === null) return open.apply(this, arguments);
    this.__ptdos = name;
  };
  P.send = function () {
    if (this.__ptdos === undefined) return send.apply(this, arguments);
    var xhr = this, name = this.__ptdos;
    setTimeout(function () {
      var b = bytes(name), response;
      if (!b) response = null;
      else if (xhr.responseType === "arraybuffer") response = b.buffer.slice(b.byteOffset, b.byteOffset + b.byteLength);
      else response = new TextDecoder("latin1").decode(b);
      Object.defineProperty(xhr, "readyState", { value: 4 });
      Object.defineProperty(xhr, "status", { value: b ? 200 : 404 });
      Object.defineProperty(xhr, "response", { value: response });
      if (typeof response === "string") Object.defineProperty(xhr, "responseText", { value: response });
      if (xhr.onreadystatechange) xhr.onreadystatechange();
      if (xhr.onload) xhr.onload();
    }, 0);
  };
  P.overrideMimeType = (function (orig) {
    return function () { if (this.__ptdos === undefined) return orig.apply(this, arguments); };
  })(P.overrideMimeType);
})();
