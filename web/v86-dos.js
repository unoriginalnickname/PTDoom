// The DOS app's page: boots FreeDOS in v86 with the game on drive C:.
//
// Everything arrives embedded as base64 (from the [gui] scripts): the
// BIOSes, the FreeDOS floppy and v86's wasm in window.V86DATA, and each game
// as a .zip in window.PTDOS_GAMES. The page unzips the games and builds a
// FAT16 hard disk from them here, so the app stores compressed games rather
// than a mostly empty disk. The floppy's AUTOEXEC.BAT runs C:\PTDOS.BAT,
// which lists the games.
(function () {
  var logEl = document.getElementById("log");
  function log(m) { logEl.textContent += m + "\n"; }
  window.onerror = function (m, s, l) { log("error: " + m + " (" + l + ")"); };
  window.addEventListener("unhandledrejection", function (e) { log("error: " + (e.reason && e.reason.message || e.reason)); });

  function decode(b64) {
    var b = atob(b64), u = new Uint8Array(b.length);
    for (var i = 0; i < b.length; i++) u[i] = b.charCodeAt(i);
    return u;
  }

  function take(name) {
    var u = decode(V86DATA[name]);
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

  // --- VGA status ---------------------------------------------------------------

  // Port 0x3DA (and 0x3BA), VGA Input Status 1, timed like a real 70 Hz card.
  // v86 flips bit 0 on every read and shows vertical retrace (bit 3) for a
  // single read per drawn frame. Wolfenstein 3D's VL_SetScreen (ID_VL_A.ASM),
  // run before its timer is hooked, waits for display (bit 0 clear) and then
  // four reads in a row of blanking without retrace (bit 0 set, bit 3 clear),
  // which v86 never gives: a black screen forever. Here each frame ends in a
  // vertical blank (bit 0 held) containing the retrace (bit 3), with bit 0
  // flickering for the horizontal blanks during display. v86 still latches
  // the start address (page flipping) on its own frames.
  function realRetrace(emu) {
    var vga = emu.v86.cpu.devices.vga, io = emu.v86.cpu.io;
    var FRAME = 1000 / 70, LINE = FRAME / 449;
    function status() {
      vga.attribute_controller_index = -1;   // as v86's own handler does
      var now = performance.now(), p = (now % FRAME) / FRAME;
      if (p >= 0.95) return p >= 0.965 && p < 0.975 ? 0x09 : 0x01;
      return (now % LINE) < LINE * 0.2 ? 0x01 : 0x00;
    }
    io.register_read(0x3DA, vga, status);
    io.register_read(0x3BA, vga, status);
  }

  // --- CD audio --------------------------------------------------------------

  // v86's CD drive has data only. Its CD commands go through PTDOS_ATAPI
  // first (tools/make_v86_app.py patches that in), and the page answers the
  // audio side: a table of contents with the game's music as audio tracks
  // after the data track, PLAY AUDIO, pause, stop, and the audio status and
  // position that DOS CD players poll (the Miles Sound System's, in Dungeon
  // Keeper). Each track is an <audio> element, decoded as it plays: all of
  // Dungeon Keeper's music decoded at once would take about 600 MB.
  var cdTracks = null;   // [{number, control, start, sectors, audio}], data track first
  var cdPlay = null;     // {track (index), end (LBA)} while playing or paused
  var cdStatus = 0x15;   // 0x11 playing, 0x12 paused, 0x13 finished, 0x15 nothing to report

  async function makeCdTracks(dataSectors, music) {
    var tracks = [{ number: 1, control: 0x14, start: 0, sectors: dataSectors }];
    var lba = dataSectors + 150;  // the 2-second gap before the first audio track
    for (var i = 0; i < music.length; i++) {
      var audio = new Audio(), m = music[i];
      audio.preload = "auto";
      audio.src = URL.createObjectURL(new Blob([m.data], { type: m.type }));
      await new Promise(function (ok, fail) {
        audio.onloadedmetadata = ok;
        audio.onerror = function () { fail(new Error("can't play " + m.name)); };
      });
      var sectors = Math.round(audio.duration * 75);
      tracks.push({ number: m.number, control: 0x10, start: lba, sectors: sectors, audio: audio });
      lba += sectors;
      m.data = null;
    }
    return tracks;
  }

  function cdEnd() { var t = cdTracks[cdTracks.length - 1]; return t.start + t.sectors; }
  function cdAddr(lba, msf) {
    if (!msf) return [lba >>> 24 & 255, lba >> 16 & 255, lba >> 8 & 255, lba & 255];
    lba += 150;
    return [0, lba / 4500 | 0, (lba / 75 | 0) % 60, lba % 75];
  }
  function cdTrackAt(lba) {
    for (var i = cdTracks.length - 1; i > 0; i--) {
      if (lba >= cdTracks[i].start && lba < cdTracks[i].start + cdTracks[i].sectors) return i;
    }
    return -1;
  }
  function cdPosition() {
    if (!cdPlay) return 0;
    var t = cdTracks[cdPlay.track];
    return t.start + Math.floor(t.audio.currentTime * 75);
  }
  function cdStart(i, seconds) {
    var a = cdTracks[i].audio;
    a.currentTime = seconds;
    var p = a.play();
    if (p && p.catch) p.catch(function (e) { log("CD music: " + e.message); });
  }
  function cdStop() {
    if (cdPlay) cdTracks[cdPlay.track].audio.pause();
    cdPlay = null;
    cdStatus = 0x15;
  }
  function cdPlayFrom(from, to) {
    cdStop();
    var i = cdTrackAt(from);
    if (i < 0) return false;
    cdPlay = { track: i, end: Math.min(to, cdEnd()) };
    cdStart(i, (from - cdTracks[i].start) / 75);
    cdStatus = 0x11;
    return true;
  }
  // Stop at the end asked for, or go on into the next track.
  setInterval(function () {
    if (!cdPlay || cdStatus !== 0x11) return;
    var t = cdTracks[cdPlay.track];
    if (cdPosition() < cdPlay.end && !t.audio.ended) return;
    if (t.audio.ended && cdPlay.end > t.start + t.sectors && cdPlay.track + 1 < cdTracks.length) {
      cdPlay.track++;
      cdStart(cdPlay.track, 0);
      return;
    }
    cdStop();
    cdStatus = 0x13;
  }, 100);

  function atapiData(ide, bytes, length) {
    ide.data_allocate(Math.min(length, bytes.length));
    ide.data.set(bytes.slice(0, ide.data_length));
    ide.data_end = ide.data_length;
    ide.status_reg = 0x58;  // ready, seek complete, data to read
  }
  function atapiDone(ide) {
    ide.data_allocate(0);
    ide.data_end = ide.data_length;
    ide.status_reg = 0x50;  // ready, seek complete
  }
  function msfLba(d, at) { return (d[at] * 60 + d[at + 1]) * 75 + d[at + 2] - 150; }

  // For testing: what the CD is playing.
  window.PTDOS_CD_STATE = function () {
    var t = cdPlay && cdTracks[cdPlay.track];
    return { status: cdStatus.toString(16), track: t ? t.number : null, seconds: t ? +t.audio.currentTime.toFixed(1) : null };
  };

  // True when the command is answered here; v86 does the rest.
  self.PTDOS_ATAPI = function (ide, cmd) {
    if (!cdTracks) return false;
    var d = ide.data, msf = (d[1] & 2) !== 0;
    switch (cmd) {
      case 0x43:  // READ TOC: format 0, from the track asked for
        if (d[9] >> 6 !== 0 || (d[2] & 15) !== 0) return false;
        var start = d[6], last = cdTracks[cdTracks.length - 1];
        var out = [0, 0, cdTracks[0].number, last.number];
        cdTracks.concat([{ number: 0xAA, control: last.control, start: cdEnd() }]).forEach(function (t) {
          if (t.number !== 0xAA && t.number < Math.max(start, 1)) return;
          out.push(0, t.control, t.number, 0);
          out.push.apply(out, cdAddr(t.start, msf));
        });
        out[1] = out.length - 2;
        atapiData(ide, out, d[7] << 8 | d[8]);
        return true;
      case 0x42:  // READ SUB-CHANNEL: audio status, and the position when asked
        var status = cdStatus, pos = cdPosition(), reply = [0, status, 0, 0];
        if (cdStatus === 0x13) cdStatus = 0x15;  // "finished" is reported once
        if ((d[2] & 0x40) && d[3] === 1) {
          var i = cdPlay ? cdPlay.track : 0, t = cdTracks[i];
          reply = reply.concat([1, t.control, t.number, 1], cdAddr(pos, msf),
                               msf ? cdAddr(pos - t.start - 150, true) : cdAddr(pos - t.start, false));
          reply[3] = 12;
        }
        atapiData(ide, reply, d[7] << 8 | d[8]);
        return true;
      case 0x5A:  // MODE SENSE (10), page 2A: a drive that plays audio
        if ((d[2] & 63) !== 0x2A) return false;
        atapiData(ide, [0, 28, 1, 0, 0, 0, 0, 0, 0x2A, 20, 3, 0, 0x71, 0x7F, 0x29, 3,
                        2, 194, 1, 0, 0, 128, 2, 194, 0, 0, 0, 0, 0, 0], d[7] << 8 | d[8]);
        return true;
      case 0x47:  // PLAY AUDIO MSF
      case 0x45:  // PLAY AUDIO (10)
      case 0xA5:  // PLAY AUDIO (12)
        var from, to;
        if (cmd === 0x47) { from = msfLba(d, 3); to = msfLba(d, 6); }
        else {
          from = (d[2] << 24 | d[3] << 16 | d[4] << 8 | d[5]) >>> 0;
          to = from + (cmd === 0x45 ? d[7] << 8 | d[8] : (d[6] << 24 | d[7] << 16 | d[8] << 8 | d[9]) >>> 0);
        }
        if (to <= from) { cdStop(); atapiDone(ide); return true; }
        if (!cdPlayFrom(from, to)) {
          ide.atapi_check_condition_response(5, 0x64);  // illegal mode for this track
          return true;
        }
        atapiDone(ide);
        return true;
      case 0x4B:  // PAUSE/RESUME
        if (cdPlay && (d[8] & 1) && cdStatus === 0x12) { cdStart(cdPlay.track, cdTracks[cdPlay.track].audio.currentTime); cdStatus = 0x11; }
        else if (cdPlay && !(d[8] & 1) && cdStatus === 0x11) { cdTracks[cdPlay.track].audio.pause(); cdStatus = 0x12; }
        atapiDone(ide);
        return true;
      case 0x4E:  // STOP PLAY/SCAN
      case 0x2B:  // SEEK
        cdStop();
        atapiDone(ide);
        return true;
      case 0x1B:  // START STOP UNIT: stopping also stops the music
        if (!(d[4] & 1)) cdStop();
        return false;
    }
    return false;
  };

  // --- boot ------------------------------------------------------------------

  // A zip whose files all sit in one folder gets that folder dropped, so
  // keen.zip holding KEEN\... becomes C:\KEEN\..., not C:\KEEN\KEEN\....
  // pt/dos-installer/installer.html guesses start commands by the same rule.
  // Decided on the files alone, like the installer, which only sees names.
  function stripCommonFolder(files) {
    var real = files.filter(function (f) { return !f.dir; });
    var first = real.length && real[0].path.split("/")[0];
    var all = first && real.every(function (f) { return f.path.indexOf(first + "/") === 0; });
    if (!all) return files;
    var prefix = first + "/";
    return files.filter(function (f) { return f.path !== prefix; }).map(function (f) {
      return f.path.indexOf(prefix) === 0 ? { path: f.path.slice(prefix.length), data: f.data, dir: f.dir } : f;
    });
  }

  function bat(lines) {
    return { path: "", data: new TextEncoder().encode(lines.join("\r\n") + "\r\n") };
  }

  // A game's CD music, as files in its zip: CDAUDIO\TRACK02.OGG and on, one
  // per audio track of the CD (MP3, WAV, FLAC and OPUS play too). They become
  // the CD's audio tracks, not files on C:.
  var CD_TRACK = /^CDAUDIO\/TRACK(\d\d)\.(OGG|MP3|WAV|FLAC|OPUS)$/i;
  var CD_TYPES = { OGG: "audio/ogg", MP3: "audio/mpeg", WAV: "audio/wav", FLAC: "audio/flac", OPUS: "audio/ogg" };

  // Each installed game ([gui]g<n>.js, from the installer) is a folder
  // C:\<NAME> with a C:\<NAME>.BAT that enters it and runs its command, so
  // typing the game's name at C:\> plays it. C:\PTDOS.BAT, run at boot,
  // lists the games.
  async function gamesDisk(games, cd) {
    var files = [], names = [], music = [], musicOf = null;
    for (var g = 0; g < games.length; g++) {
      var game = games[g], name = game.name.toUpperCase();
      stripCommonFolder(await unzip(decode(game.zip))).forEach(function (f) {
        var track = !f.dir && f.path.toUpperCase().match(CD_TRACK);
        if (track) {
          // One CD drive: the first game with music gets it.
          if (!musicOf || musicOf === name) {
            musicOf = name;
            music.push({ number: +track[1], name: f.path, type: CD_TYPES[track[2].toUpperCase()], data: f.data });
          }
          return;
        }
        files.push({ path: name + "/" + f.path, data: f.data, dir: f.dir });
      });
      var run = bat(["@echo off", "cd \\" + name].concat(game.command ? game.command.split(/\r?\n/) : []).concat(["cd \\"]));
      run.path = name + ".BAT";
      files.push(run);
      names.push(name);
      game.zip = null;
    }
    music.sort(function (a, b) { return a.number - b.number; });
    // FreeDOS tools in C:\_PTDOS, started by C:\PTDOS.BAT: the mouse driver
    // (Dungeon Keeper won't start without one), and with a CD the CD-ROM
    // driver (UDVD2, loaded by DEVLOAD) and the CD extensions (SHSUCDX).
    // They're loaded here rather than in the floppy's CONFIG.SYS so games
    // without a CD boot as before.
    var tools = [["CTMOUSE.EXE", "ctmouse"]];
    var boot = ["C:\\_PTDOS\\CTMOUSE > NUL"];
    if (cd || music.length) {
      tools.push(["DEVLOAD.COM", "devload"], ["UDVD2.SYS", "udvd2"], ["SHSUCDX.COM", "shsucdx"]);
      boot.push("C:\\_PTDOS\\DEVLOAD /Q C:\\_PTDOS\\UDVD2.SYS /D:PTDOSCD",
                "C:\\_PTDOS\\SHSUCDX /D:PTDOSCD /Q");
    }
    tools.forEach(function (d) { files.push({ path: "_PTDOS/" + d[0], data: take(d[1]) }); });
    var menu = bat(["@echo off"].concat(boot).concat(["echo.", "echo Games on C: " + names.join("  "), "echo Type a name to play it.", "echo."]));
    menu.path = "PTDOS.BAT";
    files.push(menu);
    return { disk: fat16Disk(files), names: names, count: files.filter(function (f) { return !f.dir; }).length,
             music: music, musicOf: musicOf };
  }

  async function start() {
    // No game installed yet: FreeDOS alone, no C:.
    var disk = null, games = window.PTDOS_GAMES || [];
    // The first game with a CD image (base64 ISO) gets the CD drive.
    var cd = null;
    games.forEach(function (game) {
      if (game.cd && !cd) { cd = decode(game.cd); log(game.name + ": CD " + (cd.length / 1048576).toFixed(0) + " MB"); }
      else if (game.cd) log(game.name + ": CD ignored, one CD drive only");
      game.cd = null;
    });
    if (games.length) {
      var made = await gamesDisk(games, cd);
      disk = made.disk;
      log(made.names.join(", ") + ": " + made.count + " files, " + (disk.length / 1048576).toFixed(0) + " MB disk");
      // Music with no CD image: an empty data track, then the music.
      if (made.music.length && !cd) cd = take("cdempty");
      if (cd) {
        cdTracks = await makeCdTracks(cd.length / 2048, made.music);
        if (made.music.length) log(made.musicOf + ": CD music, " + made.music.length + " tracks");
      }
    } else {
      log("no games installed");
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
    if (cd && disk) options.cdrom = { buffer: cd.buffer };
    var emu = new V86(options);
    window.emu = emu;
    var opl = take("opl");
    emu.add_listener("emulator-loaded", function () {
      realRetrace(emu);
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

  // A DOS mouse only reports movement, so the page's own pointer and a game's
  // cursor drift apart. The page's pointer is hidden over the screen (the
  // page's CSS, tools/make_v86_app.py), so only the game's cursor shows;
  // pushing to a window edge lines them up again, as in a windowed DOSBox.
  // A PC's window in Packet Tracer 9.0.1 refuses pointer
  // lock silently, but clicking still asks for it (hidden and unbounded; Esc
  // releases it) in case a window allows it. Asked only while unlocked:
  // js-dos asking on every click gave a stream of prompts.
  var screenEl = document.getElementById("screen");
  screenEl.addEventListener("mousedown", function () {
    if (document.pointerLockElement !== screenEl && screenEl.requestPointerLock) {
      try { var p = screenEl.requestPointerLock(); if (p && p.catch) p.catch(function () {}); } catch (e) {}
    }
  });
  start().catch(function (e) { log("error: " + e.message); });
})();
