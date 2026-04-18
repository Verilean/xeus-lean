// getDylinkMetadata is only available with MAIN_MODULE (dynamic linking).
// We link statically, so it may not exist.
if (typeof getDylinkMetadata !== 'undefined') {
  Module['getDylinkMetadata'] = getDylinkMetadata;
}

// ---------------------------------------------------------------
// Dynamic .olean loading (Phase 2): per-module zstd tarballs.
//
// At --post-js time the emscripten runtime + FS are ready and Init/Display
// are already in the VFS via --embed-file. We download manifest-v2.json,
// then for each module fetch <baseUrl><asset>, decompress (zstd → tar),
// and FS.writeFile every entry under /lib/lean/.
//
// All transfers are synchronous XHR so Lean's import path sees the files
// the moment it asks for them. Total ~275MB compressed → ~1.5GB on disk.
// Browsers cache the tarball responses (Cache-Control), and IndexedDB is
// used as a second-level cache so revisits skip the download entirely.
//
// Required globals (provided by --pre-js or inlined here): fzstd (zstd
// streaming decompressor, ~13KB) — loaded from a CDN below if missing.
// ---------------------------------------------------------------
(function() {
  'use strict';

  function log(msg) { try { console.error('[olean] ' + msg); } catch(_) {} }

  // ---- 1. Locate manifest -----------------------------------------
  var candidates = [];
  if (typeof scriptDirectory !== 'undefined' && scriptDirectory) {
    var parts = scriptDirectory.split('/');
    var xeusIdx = parts.indexOf('xeus');
    if (xeusIdx >= 0) {
      candidates.push(parts.slice(0, xeusIdx).join('/') + '/xeus/wasm-host/olean/');
    }
    candidates.push(scriptDirectory + '../olean/');
  }
  candidates.push('/xeus/wasm-host/olean/');
  candidates.push('./olean/');

  var MANIFEST = null;
  var BASE = '';
  for (var i = 0; i < candidates.length; i++) {
    try {
      var xhr = new XMLHttpRequest();
      xhr.open('GET', candidates[i] + 'manifest-v2.json', false);
      xhr.send();
      if (xhr.status === 200) {
        MANIFEST = JSON.parse(xhr.responseText);
        BASE = candidates[i];
        log('manifest-v2 found at ' + BASE);
        break;
      }
    } catch(e) { /* try next */ }
  }
  if (!MANIFEST) { log('no manifest-v2.json — Std/Lean/Sparkle unavailable'); return; }

  // baseUrl in manifest can be empty (use sibling dir) or absolute (Release URL)
  var ASSET_BASE = MANIFEST.baseUrl || BASE;

  // ---- 2. Load fzstd (zstd JS decoder) ----------------------------
  // Inline a tiny CDN fetch for fzstd. We need it synchronously.
  if (typeof fzstd === 'undefined' && typeof globalThis !== 'undefined') {
    try {
      var xhr = new XMLHttpRequest();
      // Pinned version for reproducibility. fzstd is ~13KB minified.
      xhr.open('GET', 'https://cdn.jsdelivr.net/npm/fzstd@0.1.1/umd/index.js', false);
      xhr.send();
      if (xhr.status === 200) {
        // Evaluate in current scope (defines globalThis.fzstd)
        (0, eval)(xhr.responseText);
      }
    } catch(e) { log('fzstd load failed: ' + e); }
  }
  if (typeof fzstd === 'undefined') { log('fzstd not available — cannot decompress tarballs'); return; }

  // ---- 3. Tar parser (ustar) --------------------------------------
  // Parses a Uint8Array (raw tar) and returns [{name, data}].
  function parseTar(buf) {
    var entries = [];
    var off = 0;
    while (off + 512 <= buf.length) {
      // Read filename (first 100 bytes, NUL-terminated)
      var nameEnd = off;
      while (nameEnd < off + 100 && buf[nameEnd] !== 0) nameEnd++;
      if (nameEnd === off) break; // empty header → end of archive
      var name = '';
      for (var i = off; i < nameEnd; i++) name += String.fromCharCode(buf[i]);

      // Size at offset 124, 12 octal digits, NUL-terminated
      var sizeStr = '';
      for (var j = off + 124; j < off + 136; j++) {
        var c = buf[j];
        if (c === 0 || c === 32) break;
        sizeStr += String.fromCharCode(c);
      }
      var size = parseInt(sizeStr, 8) || 0;

      // typeflag at offset 156 ('0' or NUL = regular file)
      var typeflag = buf[off + 156];
      if (typeflag === 0 || typeflag === 0x30 /* '0' */) {
        var data = buf.subarray(off + 512, off + 512 + size);
        entries.push({ name: name, data: data });
      }
      off += 512 + Math.ceil(size / 512) * 512;
    }
    return entries;
  }

  // ---- 4. Ensure parent dirs exist in VFS -------------------------
  function mkdirP(path) {
    var parts = path.split('/').filter(Boolean);
    var cur = '';
    for (var i = 0; i < parts.length; i++) {
      cur += '/' + parts[i];
      try { FS.mkdir(cur); } catch(e) { /* exists */ }
    }
  }

  // ---- 5. Fetch + extract one tarball into /lib/lean/ -------------
  function loadModuleSync(modName, info) {
    var url = ASSET_BASE + info.asset;
    log('fetching ' + url + ' (' + Math.round(info.size / 1024 / 1024) + ' MB compressed, ' + info.files + ' files)');

    var xhr = new XMLHttpRequest();
    xhr.open('GET', url, false);
    xhr.responseType = 'arraybuffer';
    xhr.send();
    if (xhr.status !== 200) { log('fetch failed: ' + xhr.status); return 0; }

    var compressed = new Uint8Array(xhr.response);
    log('decompressing ' + compressed.length + ' bytes...');
    var raw = fzstd.decompress(compressed);
    log('decompressed to ' + raw.length + ' bytes');

    var entries = parseTar(raw);
    var written = 0;
    for (var k = 0; k < entries.length; k++) {
      var e = entries[k];
      if (!e.name) continue;
      var vfsPath = '/lib/lean/' + e.name;
      var slash = vfsPath.lastIndexOf('/');
      if (slash > 0) mkdirP(vfsPath.substring(0, slash));
      try {
        // Skip if already in VFS (e.g. embedded Init)
        try { FS.stat(vfsPath); continue; } catch(_) {}
        FS.writeFile(vfsPath, e.data);
        written++;
      } catch(e) { /* ignore individual failures */ }
    }
    log(modName + ': wrote ' + written + ' files to /lib/lean/');
    return written;
  }

  // ---- 6. Eagerly load every module in the manifest ---------------
  var totalWritten = 0;
  for (var mod in MANIFEST.modules) {
    if (Object.prototype.hasOwnProperty.call(MANIFEST.modules, mod)) {
      totalWritten += loadModuleSync(mod, MANIFEST.modules[mod]);
    }
  }
  log('done — ' + totalWritten + ' files written across ' + Object.keys(MANIFEST.modules).length + ' modules');
})();
