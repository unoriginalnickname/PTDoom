// The DOS app's page: boots FreeDOS in v86 with the game on drive C:.
//
// Everything arrives embedded as base64 in window.V86DATA (from the [gui]
// scripts): the BIOSes, the FreeDOS floppy, v86's wasm and the game as a
// .zip. The page unzips the game and builds a FAT16 hard disk from it here,
// so the app stores the compressed game rather than a mostly empty disk.
// The floppy's AUTOEXEC.BAT runs C:\PTDOS.BAT, which starts the game.
(function () {
  var logEl = document.getElementById("log");
  function log(m) { logEl.textContent += m + "\n"; }
  window.onerror = function (m, s, l) { log("error: " + m + " (" + l + ")"); };
  window.addEventListener("unhandledrejection", function (e) { log("error: " + (e.reason && e.reason.message || e.reason)); });

  function take(name) {
    var b = atob(V86DATA[name]), u = new Uint8Array(b.length);
    for (var i = 0; i < b.length; i++) u[i] = b.charCodeAt(i);
    delete V86DATA[name];
    return u;
  }

  // --- zip ---------------------------------------------------------------

  async function inflate(data) {
    var stream = new Blob([data]).stream().pipeThrough(new DecompressionStream("deflate-raw"));
    return new Uint8Array(await new Response(stream).arrayBuffer());
  }

  // Returns [{path, data}] for the files in a zip, and [{path, dir: true}]
  // for its folders (empty ones matter: games expect their save folder).
  async function unzip(zip) {
    var v = new DataView(zip.buffer, zip.byteOffset, zip.byteLength);
    var eocd = -1;
    for (var i = zip.length - 22; i >= Math.max(0, zip.length - 65557); i--) {
      if (v.getUint32(i, true) === 0x06054b50) { eocd = i; break; }
    }
    if (eocd < 0) throw new Error("not a zip file");
    var count = v.getUint16(eocd + 10, true), at = v.getUint32(eocd + 16, true), out = [];
    for (var n = 0; n < count; n++) {
      if (v.getUint32(at, true) !== 0x02014b50) throw new Error("bad zip directory");
      var method = v.getUint16(at + 10, true);
      var packed = v.getUint32(at + 20, true), size = v.getUint32(at + 24, true);
      var nameLen = v.getUint16(at + 28, true), extraLen = v.getUint16(at + 30, true), commentLen = v.getUint16(at + 32, true);
      var local = v.getUint32(at + 42, true);
      var path = new TextDecoder("latin1").decode(zip.subarray(at + 46, at + 46 + nameLen)).replace(/\\/g, "/");
      at += 46 + nameLen + extraLen + commentLen;
      if (/\/$/.test(path)) { out.push({ path: path, dir: true }); continue; }
      var start = local + 30 + v.getUint16(local + 26, true) + v.getUint16(local + 28, true);
      var raw = zip.subarray(start, start + packed);
      var data;
      if (method === 0) data = raw.slice();
      else if (method === 8) data = await inflate(raw);
      else throw new Error(path + ": unsupported zip compression " + method);
      if (data.length !== size) throw new Error(path + ": unzipped to the wrong size");
      out.push({ path: path, data: data });
    }
    return out;
  }

  // --- FAT16 disk ----------------------------------------------------------

  var SECTOR = 512, HEADS = 16, SPT = 63, PART_START = SPT;

  // DOS 8.3 name, as the 11 bytes of a directory entry.
  function shortName(name, taken) {
    var up = name.toUpperCase(), dot = up.lastIndexOf(".");
    var base = dot > 0 ? up.slice(0, dot) : up, ext = dot > 0 ? up.slice(dot + 1) : "";
    var clean = function (s) { return s.replace(/[^A-Z0-9!#$%&'()\-@^_`{}~]/g, "_"); };
    var b = clean(base), e = clean(ext).slice(0, 3);
    var fits = b === base && b.length <= 8 && e === ext;
    var key = fits ? b.padEnd(8) + e.padEnd(3) : null;
    for (var k = 1; !key || taken[key]; k++) {
      var tail = "~" + k;
      key = (b.slice(0, 8 - tail.length) + tail).padEnd(8) + e.padEnd(3);
    }
    taken[key] = true;
    return key;
  }

  // files: [{path, data}]. Returns the whole disk: MBR, one FAT16 partition.
  function fat16Disk(files) {
    // Folder tree.
    var root = { dirs: {}, files: [] };
    files.forEach(function (f) {
      var parts = f.path.split("/").filter(Boolean), node = root;
      var depth = f.dir ? parts.length : parts.length - 1;
      for (var i = 0; i < depth; i++) {
        node = node.dirs[parts[i]] = node.dirs[parts[i]] || { dirs: {}, files: [] };
      }
      if (!f.dir) node.files.push({ name: parts[parts.length - 1], data: f.data });
    });

    var dataBytes = files.reduce(function (s, f) { return s + (f.dir ? 0 : f.data.length); }, 0);
    // Room for the game plus 16 MB for saves, at least 32 MB, whole cylinders.
    var cyl = HEADS * SPT;
    var total = Math.max(32 * 2048, Math.ceil((dataBytes * 1.1) / SECTOR) + 16 * 2048);
    total = Math.ceil(total / cyl) * cyl;
    var partSectors = total - PART_START;
    var spc = 1;
    while (partSectors / spc > 65000) spc *= 2;
    if (spc > 64) throw new Error("game too big for a FAT16 disk");
    var clusterBytes = spc * SECTOR;
    var rootEntries = 512, rootSectors = rootEntries * 32 / SECTOR;
    var fatSectors = Math.ceil((partSectors / spc + 2) * 2 / SECTOR);
    var dataStart = 1 + 2 * fatSectors + rootSectors;
    var clusters = Math.floor((partSectors - dataStart) / spc);
    if (clusters < 4085) throw new Error("disk too small for FAT16");

    var disk = new Uint8Array(total * SECTOR), dv = new DataView(disk.buffer);
    var base = PART_START * SECTOR;
    var fat = new Uint16Array(clusters + 2);
    fat[0] = 0xFFF8; fat[1] = 0xFFFF;
    var next = 2;

    function alloc(bytes) {
      var n = Math.max(1, Math.ceil(bytes / clusterBytes)), first = next;
      if (first + n > clusters + 2) throw new Error("disk full");
      for (var c = first; c < first + n - 1; c++) fat[c] = c + 1;
      fat[first + n - 1] = 0xFFFF;
      next += n;
      return first;
    }
    function clusterOffset(c) { return base + (dataStart + (c - 2) * spc) * SECTOR; }

    var DATE = ((1995 - 1980) << 9) | (1 << 5) | 1;
    function entry(buf, at, name11, attr, cluster, size) {
      for (var i = 0; i < 11; i++) buf[at + i] = name11.charCodeAt(i);
      buf[at + 11] = attr;
      var d = new DataView(buf.buffer, buf.byteOffset + at, 32);
      d.setUint16(24, DATE, true);
      d.setUint16(26, cluster, true);
      d.setUint32(28, size, true);
    }

    // Writes a folder's entries into buf (its own clusters, or the root area).
    function writeDir(node, buf, selfCluster, parentCluster) {
      var at = 0, taken = {};
      if (selfCluster) {
        entry(buf, 0, ".          ", 0x10, selfCluster, 0);
        entry(buf, 32, "..         ", 0x10, parentCluster, 0);
        at = 64;
      }
      Object.keys(node.dirs).forEach(function (name) {
        var child = node.dirs[name];
        var n = Object.keys(child.dirs).length + child.files.length + 2;
        var bytes = Math.ceil(n * 32 / clusterBytes) * clusterBytes;
        var c = alloc(bytes);
        entry(buf, at, shortName(name, taken), 0x10, c, 0);
        at += 32;
        writeDir(child, disk.subarray(clusterOffset(c), clusterOffset(c) + bytes), c, selfCluster);
      });
      node.files.forEach(function (f) {
        var c = f.data.length ? alloc(f.data.length) : 0;
        if (c) disk.set(f.data, clusterOffset(c));
        entry(buf, at, shortName(f.name, taken), 0x20, c, f.data.length);
        at += 32;
      });
      if (at > buf.length) throw new Error("too many files in one folder");
    }
    var rootOff = base + (1 + 2 * fatSectors) * SECTOR;
    if (Object.keys(root.dirs).length + root.files.length > rootEntries) throw new Error("too many files in the top folder");
    writeDir(root, disk.subarray(rootOff, rootOff + rootSectors * SECTOR), 0, 0);

    // FATs.
    var fatBytes = new Uint8Array(fat.buffer);
    for (var k = 0; k < 2; k++) disk.set(fatBytes, base + (1 + k * fatSectors) * SECTOR);

    // Boot sector with the BPB (not bootable: FreeDOS boots from the floppy).
    var bs = base;
    disk.set([0xEB, 0x3C, 0x90], bs);
    "PTDOS   ".split("").forEach(function (ch, i) { disk[bs + 3 + i] = ch.charCodeAt(0); });
    dv.setUint16(bs + 11, SECTOR, true);
    disk[bs + 13] = spc;
    dv.setUint16(bs + 14, 1, true);
    disk[bs + 16] = 2;
    dv.setUint16(bs + 17, rootEntries, true);
    dv.setUint16(bs + 19, partSectors < 65536 ? partSectors : 0, true);
    disk[bs + 21] = 0xF8;
    dv.setUint16(bs + 22, fatSectors, true);
    dv.setUint16(bs + 24, SPT, true);
    dv.setUint16(bs + 26, HEADS, true);
    dv.setUint32(bs + 28, PART_START, true);
    dv.setUint32(bs + 32, partSectors < 65536 ? 0 : partSectors, true);
    disk[bs + 36] = 0x80;
    disk[bs + 38] = 0x29;
    dv.setUint32(bs + 39, 0x50544F53, true);
    "PTDOS      FAT16   ".split("").forEach(function (ch, i) { disk[bs + 43 + i] = ch.charCodeAt(0); });
    disk[bs + 510] = 0x55; disk[bs + 511] = 0xAA;

    // MBR: one active partition, 0x06 (FAT16) or 0x04 (FAT16 under 32 MB).
    function chs(lba) {
      var c = Math.floor(lba / cyl), r = lba % cyl, h = Math.floor(r / SPT), s = r % SPT + 1;
      return [h, (s & 0x3F) | ((c >> 2) & 0xC0), c & 0xFF];
    }
    disk[446] = 0x80;
    disk.set(chs(PART_START), 447);
    disk[450] = partSectors < 65536 ? 0x04 : 0x06;
    disk.set(chs(total - 1), 451);
    dv.setUint32(454, PART_START, true);
    dv.setUint32(458, partSectors, true);
    disk[510] = 0x55; disk[511] = 0xAA;
    return disk;
  }

  // --- FM music ---------------------------------------------------------------

  // v86's SB16 ignores the FM chip, so the OPL ports are taken over here and
  // played through Nuked OPL3 (V86DATA.opl, built by tools/build_opl.py).
  // Each register write is timestamped and applied at the matching sample of
  // the output, so notes keep their timing within an audio buffer.
  async function attachOpl(emu, wasmBytes) {
    var inst = (await WebAssembly.instantiate(wasmBytes, {})).instance.exports;
    if (inst._initialize) inst._initialize();
    var ctx = new window.AudioContext();
    var rate = ctx.sampleRate;
    inst.opl_reset(rate);

    var queue = [], renderT = 0;   // [time ms, register, value]...
    var addr = [0, 0], status = 0, masks = 0;

    function write(reg, value) {
      if (reg === 0x04) {
        // Timer control. A started timer "expires" at once: enough for the
        // AdLib detection games do, and music doesn't use the chip's timers.
        if (value & 0x80) { status = 0; return; }
        masks = value & 0x60;
        if ((value & 1) && !(masks & 0x40)) status |= 0xC0;
        if ((value & 2) && !(masks & 0x20)) status |= 0xA0;
        return;
      }
      if (reg === 0x02 || reg === 0x03) return;
      if (ctx.state !== "running") { inst.opl_write(reg, value); return; }
      queue.push(performance.now(), reg, value);
    }

    var dev = {}, io = emu.v86.cpu.io;
    function status8() { return status; }
    [0x388, 0x220, 0x228].forEach(function (p) {
      io.register_write(p, dev, function (v) { addr[0] = v; });
      io.register_write(p + 1, dev, function (v) { write(addr[0], v); });
      io.register_read(p, dev, status8);
    });
    [0x38A, 0x222].forEach(function (p) {
      io.register_write(p, dev, function (v) { addr[1] = v; });
      io.register_write(p + 1, dev, function (v) { write(0x100 | addr[1], v); });
      io.register_read(p, dev, status8);
    });

    var node = ctx.createScriptProcessor(2048, 0, 2);
    node.onaudioprocess = function (e) {
      var n = e.outputBuffer.length, left = e.outputBuffer.getChannelData(0), right = e.outputBuffer.getChannelData(1);
      var bufMs = n * 1000 / rate, now = performance.now();
      if (renderT < now - 3 * bufMs || renderT > now) renderT = now - bufMs;
      var q = 0, i = 0;
      function at(k) { return Math.round((queue[k] - renderT) * rate / 1000); }
      while (i < n) {
        while (q < queue.length && at(q) <= i) { inst.opl_write(queue[q + 1], queue[q + 2]); q += 3; }
        var end = q < queue.length ? Math.min(n, Math.max(i + 1, at(q))) : n;
        var ptr = inst.opl_render(end - i);
        var pcm = new Int16Array(inst.memory.buffer, ptr, 2 * (end - i));
        for (var s = 0; s < end - i; s++) {
          left[i + s] = pcm[2 * s] / 32768;
          right[i + s] = pcm[2 * s + 1] / 32768;
        }
        i = end;
      }
      queue = queue.slice(q);
      renderT += bufMs;
    };
    node.connect(ctx.destination);
  }

  // --- boot ------------------------------------------------------------------

  async function start() {
    // No game installed yet ([gui]game.js missing): FreeDOS alone, no C:.
    var disk = null;
    if (V86DATA.game) {
      var files = await unzip(take("game"));
      disk = fat16Disk(files);
      log(files.filter(function (f) { return !f.dir; }).length + " files, " + (disk.length / 1048576).toFixed(0) + " MB disk");
    } else {
      log("no game installed");
    }
    var wasm = take("wasm");
    var options = {
      wasm_fn: function (imports) {
        return WebAssembly.instantiate(wasm, imports).then(function (r) { return r.instance.exports; });
      },
      memory_size: 32 * 1024 * 1024,
      vga_memory_size: 2 * 1024 * 1024,
      screen_container: document.getElementById("screen"),
      bios: { buffer: take("bios").buffer },
      vga_bios: { buffer: take("vgabios").buffer },
      fda: { buffer: take("fda").buffer },
      boot_order: 0x321,
      autostart: true
    };
    if (disk) options.hda = { buffer: disk.buffer };
    var emu = new V86(options);
    window.emu = emu;
    var opl = take("opl");
    emu.add_listener("emulator-loaded", function () {
      attachOpl(emu, opl).then(function () { log("FM music on"); }, function (e) { log("FM music failed: " + e.message); });
    });
    setTimeout(function () {
      log("audio: " + (contexts.map(function (c) { return c.state; }).join(", ") || "none") +
          (window.AudioWorklet ? ", AudioWorklet still on" : ""));
    }, 3000);
    setTimeout(function () { logEl.style.display = "none"; }, 12000);
  }

  // Packet Tracer's AudioWorklet crackles and slows v86 down; without it v86
  // uses its older player, which sounds right.
  try { delete window.AudioWorklet; window.AudioWorklet = undefined; } catch (e) {}

  // In a PC's window the AudioContext starts suspended (autoplay rules), and
  // v86 never resumes it after a click or key. Keep the page's contexts and
  // resume them on every key and click (cheap once they're running).
  var contexts = [], RealAudioContext = window.AudioContext;
  window.AudioContext = function (opts) {
    var ctx = new RealAudioContext(opts);
    contexts.push(ctx);
    return ctx;
  };
  window.AudioContext.prototype = RealAudioContext.prototype;
  function resumeAudio() {
    contexts.forEach(function (ctx) { if (ctx.state === "suspended") ctx.resume(); });
  }
  ["keydown", "mousedown", "pointerdown", "touchstart"].forEach(function (type) {
    window.addEventListener(type, resumeAudio, true);
  });
  start().catch(function (e) { log("error: " + e.message); });
})();
