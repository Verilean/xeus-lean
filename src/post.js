// getDylinkMetadata is only available with MAIN_MODULE (dynamic linking).
// We link statically, so it may not exist.
if (typeof getDylinkMetadata !== 'undefined') {
  Module['getDylinkMetadata'] = getDylinkMetadata;
}

// fzstd is loaded by an earlier --post-js (src/fzstd.umd.js); see
// CMakeLists.txt. Bundling avoids a runtime CDN fetch from the worker
// thread where cross-origin XHR can be blocked by JupyterLite's
// service worker.

// ---------------------------------------------------------------
// Dynamic .olean loading (Phase 2): per-module zstd tarballs.
//
// We download manifest-v2.json, then for each module fetch
// <baseUrl><asset>, decompress (zstd → tar), and FS.writeFile each
// entry under /lib/lean/.
//
// Run in `Module.preRun`: at --post-js time FS exists but the wasm
// module is still being instantiated (FS.writeFile only works after
// the wasm runtime side of FS is up). preRun fires AFTER FS is fully
// usable but BEFORE main(); main() is when the kernel reads its
// olean files, so writes here land in time.
//
// Failures here are logged but never throw — a kernel that boots
// without Std/Lean/Sparkle/Hesper is still useful for Init-only code.
// ---------------------------------------------------------------
Module.preRun = Module.preRun || [];
Module.preRun.push(function () {
  'use strict';

  var T0 = (typeof performance !== 'undefined' && performance.now)
    ? performance.now() : Date.now();
  function ts() {
    var now = (typeof performance !== 'undefined' && performance.now)
      ? performance.now() : Date.now();
    return '+' + Math.round(now - T0) + 'ms';
  }
  function log(msg) { try { console.error('[olean ' + ts() + '] ' + msg); } catch(_) {} }

  // We used to do `new XMLHttpRequest(); xhr.open(..., false)` (sync XHR)
  // but JupyterLite's service worker on GitHub Pages silently fails the
  // request — the response never reaches the worker thread, the manifest
  // is treated as missing, and the kernel boots with no Init/Std/Lean
  // modules. Switch to async fetch + Module.addRunDependency, which lets
  // emscripten block the wasm `main()` until the tarballs are unpacked.

  if (typeof fetch !== 'function') {
    log('fetch unavailable — skipping dynamic olean load');
    return;
  }

  // ---- 1. Locate manifest -----------------------------------------
  // Debug: emscripten environment vars that influence URL resolution
  try {
    log('scriptDirectory=' + (typeof scriptDirectory !== 'undefined' ? scriptDirectory : '<undefined>'));
    if (typeof location !== 'undefined' && location) {
      log('location.href=' + (location.href || '<unset>'));
      log('location.pathname=' + (location.pathname || '<unset>'));
    } else {
      log('location=<undefined>');
    }
  } catch (_) {}

  // Build candidate base URLs.
  //
  // Tricky case: on GitHub Pages the kernel ships under
  //   /<repo>/extensions/@jupyterlite/xeus-extension/static/...
  // and the olean assets are at
  //   /<repo>/xeus/wasm-host/olean/
  // The previous version split on `xeus` to find the site root, but
  // `xeus-extension` contains "xeus" as a substring (not a path
  // segment) — actually `indexOf('xeus')` returns -1 in that case
  // (path segments are "xeus-lean", "xeus-extension"; no segment is
  // literally "xeus"), so the split-on-'xeus' branch silently does
  // nothing on Pages.
  //
  // Strategy: peel known JupyterLite asset roots off `location.pathname`
  // ('/lab/', '/extensions/', '/files/', '/repl/', '/tree/') to
  // recover the site root, then append 'xeus/wasm-host/olean/'.
  var candidates = [];
  try {
    if (typeof location !== 'undefined' && location && location.pathname) {
      var pn = location.pathname;
      var siteRoot = pn;
      var markers = ['/lab/', '/extensions/', '/files/', '/repl/', '/tree/'];
      for (var mi = 0; mi < markers.length; mi++) {
        var idx = pn.indexOf(markers[mi]);
        if (idx >= 0) { siteRoot = pn.substring(0, idx); break; }
      }
      // If no marker matched, fall back to the directory containing
      // the current resource.
      if (siteRoot === pn) siteRoot = pn.replace(/\/[^\/]*$/, '');
      if (!siteRoot.endsWith('/')) siteRoot += '/';
      candidates.push(siteRoot + 'xeus/wasm-host/olean/');
    }
  } catch (_) {}

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

  var depTag = 'olean-dynamic-load';
  Module.addRunDependency(depTag);

  log('candidates: ' + JSON.stringify(candidates));

  (async function loadOleans() {
    var MANIFEST = null;
    var BASE = '';
    for (var i = 0; i < candidates.length; i++) {
      var url = candidates[i] + 'manifest-v2.json';
      try {
        var resp = await fetch(url);
        log('try ' + url + ' -> ' + resp.status);
        if (resp.ok) {
          try {
            MANIFEST = await resp.json();
            BASE = candidates[i];
            log('manifest-v2 found at ' + BASE);
            break;
          } catch (parseErr) {
            log('manifest-v2 at ' + url + ' did not parse: ' + parseErr);
          }
        }
      } catch (e) { log('fetch ' + url + ' threw: ' + e); }
    }
    if (!MANIFEST) {
      log('no manifest-v2.json — only embedded modules will work');
      Module.removeRunDependency(depTag);
      return;
    }

    if (typeof fzstd === 'undefined' || typeof fzstd.decompress !== 'function') {
      log('fzstd not loaded — cannot decompress tarballs (skipping)');
      Module.removeRunDependency(depTag);
      return;
    }

    var ASSET_BASE = MANIFEST.baseUrl || BASE;

  // ---- 2. Tar parser (ustar regular files only) -------------------
  function parseTar(buf) {
    var entries = [];
    var off = 0;
    while (off + 512 <= buf.length) {
      var nameEnd = off;
      while (nameEnd < off + 100 && buf[nameEnd] !== 0) nameEnd++;
      if (nameEnd === off) break;
      var name = '';
      for (var i = off; i < nameEnd; i++) name += String.fromCharCode(buf[i]);
      var sizeStr = '';
      for (var j = off + 124; j < off + 136; j++) {
        var c = buf[j];
        if (c === 0 || c === 32) break;
        sizeStr += String.fromCharCode(c);
      }
      var size = parseInt(sizeStr, 8) || 0;
      var typeflag = buf[off + 156];
      if (typeflag === 0 || typeflag === 0x30) {
        entries.push({ name: name, data: buf.subarray(off + 512, off + 512 + size) });
      }
      off += 512 + Math.ceil(size / 512) * 512;
    }
    return entries;
  }

  // ---- 3. Ensure parent dirs exist in VFS -------------------------
  function mkdirP(path) {
    var parts = path.split('/').filter(Boolean);
    var cur = '';
    for (var i = 0; i < parts.length; i++) {
      cur += '/' + parts[i];
      try { FS.mkdir(cur); } catch(e) { /* exists */ }
    }
  }

  // ---- 4a. IndexedDB cache for compressed tarballs ----------------
  //
  // First-run cost per module:
  //   network fetch (HTTPS) → fzstd.decompress → parseTar → write
  // We cache the *compressed* bytes (the .tar.zst as a single
  // ArrayBuffer) keyed by asset name + size.  On cache hit we
  // skip the network round-trip and go straight to decompress +
  // parse + write.
  //
  // Why not cache the parsed entries?  Earlier revisions stored
  // the post-parseTar Array<{name, data: Uint8Array}> directly.
  // Structured-clone of that array forces the browser to copy
  // every entry's Uint8Array into the IDB transaction buffer at
  // once.  For Lean that's 1.3 GB of live bytes during put(),
  // which OOMs in worker contexts.  Storing the raw compressed
  // blob (~85 MB for Lean, ~370 MB total across all modules)
  // sidesteps that — one Uint8Array per module, structured-clone
  // is cheap.  Decompress+parse on the hit path takes a few
  // seconds, still far better than a fresh network fetch.
  //
  // Worker contexts have IndexedDB (everywhere we care about);
  // if it's not there we just degrade to the original path.
  var DB_NAME = 'xlean-olean-cache';
  var DB_VERSION = 1;
  var STORE = 'modules';

  function openDB() {
    return new Promise(function (resolve, reject) {
      if (typeof indexedDB === 'undefined') { reject(new Error('no IDB')); return; }
      var req = indexedDB.open(DB_NAME, DB_VERSION);
      req.onupgradeneeded = function (ev) {
        var db = ev.target.result;
        if (!db.objectStoreNames.contains(STORE)) db.createObjectStore(STORE);
      };
      req.onsuccess = function () { resolve(req.result); };
      req.onerror   = function () { reject(req.error); };
    });
  }
  function idbGet(db, key) {
    return new Promise(function (resolve, reject) {
      var tx = db.transaction(STORE, 'readonly');
      var rq = tx.objectStore(STORE).get(key);
      rq.onsuccess = function () { resolve(rq.result); };
      rq.onerror   = function () { reject(rq.error); };
    });
  }
  function idbPut(db, key, val) {
    return new Promise(function (resolve, reject) {
      var tx = db.transaction(STORE, 'readwrite');
      var rq = tx.objectStore(STORE).put(val, key);
      rq.onsuccess = function () { resolve(); };
      rq.onerror   = function () { reject(rq.error); };
    });
  }

  var dbPromise = openDB().catch(function () { return null; });

  // ---- 4b. Fetch + extract one tarball into /lib/lean/ ------------
  //
  // Two cache levels.  The "expanded" cache stores the post-
  // decompress / post-parseTar state — a Blob of the raw tar bytes
  // plus a compact { names, offsets, lengths } index — keyed under
  //   modName|asset|size|EXPANDED-V1
  // On hit we skip both fzstd.decompress (≈9 s for Lean) and tar
  // parsing entirely.
  //
  // Falls back to the "compressed" cache (Blob of the .tar.zst as
  // shipped) so a partial migration still helps.  And finally
  // falls back to fetch + decompress + parse + save-to-both.
  //
  // Why Blob + sidecar index instead of Array<{name,data}>?
  // structured-cloning Uint8Array always allocates a fresh
  // ArrayBuffer per entry, even when 7000 entries share the
  // same backing buffer.  For Lean that's 1.3 GB → 2 × 1.3 GB
  // peak during put(), which OOMed the worker.  Storing the raw
  // bytes in a Blob (file-backed in Chromium) and the metadata
  // as a tiny JS object sidesteps that — put() copies only the
  // names + numbers, while the Blob is referenced.
  async function loadModule(modName, info) {
    var cacheKey = modName + '|' + info.asset + '|' + info.size;
    var expandedKey = cacheKey + '|EXPANDED-V1';
    var db = await dbPromise;

    // (A) Try expanded cache first.
    if (db) {
      try {
        var cached = await idbGet(db, expandedKey);
        if (cached && cached.raw instanceof Blob &&
            Array.isArray(cached.names) &&
            cached.offsets instanceof Uint32Array &&
            cached.lengths instanceof Uint32Array &&
            cached.names.length === cached.offsets.length) {
          var tHit = (typeof performance !== 'undefined') ? performance.now() : 0;
          var ab = await cached.raw.arrayBuffer();
          var raw = new Uint8Array(ab);
          var tWrite = (typeof performance !== 'undefined') ? performance.now() : 0;
          log(modName + ': expanded-cache hit, ' + Math.round(raw.length/1024/1024) + 'MB Blob → AB in ' + Math.round(tWrite - tHit) + 'ms');
          return writeEntriesFromBuffer(modName, raw, cached.names, cached.offsets, cached.lengths);
        }
      } catch (e) { /* fall through */ }
    }

    // (B) Try compressed-tarball cache.
    var compressed = null;
    if (db) {
      try {
        var cached2 = await idbGet(db, cacheKey);
        var ab2 = null;
        if (cached2 instanceof Blob) ab2 = await cached2.arrayBuffer();
        else if (cached2 instanceof Uint8Array) ab2 = cached2.buffer;
        else if (cached2 instanceof ArrayBuffer) ab2 = cached2;
        if (ab2) {
          compressed = new Uint8Array(ab2);
          log(modName + ': compressed-cache hit (' + Math.round(compressed.byteLength / 1024 / 1024) + ' MB)');
        }
      } catch (e) { /* fall through */ }
    }

    // (C) Fetch from network if neither cache hit.
    var compressedBlob = null;
    if (!compressed) {
      var url = ASSET_BASE + info.asset;
      log('fetching ' + url + ' (' + Math.round(info.size / 1024 / 1024) + ' MB compressed, ' + info.files + ' files)');
      try {
        var resp = await fetch(url);
        if (!resp.ok) { log(modName + ': fetch failed status=' + resp.status); return 0; }
        compressedBlob = await resp.blob();
        var fetchAb = await compressedBlob.arrayBuffer();
        compressed = new Uint8Array(fetchAb);
      } catch (e) { log(modName + ': fetch error: ' + e); return 0; }

      if (db && compressedBlob) {
        try {
          await idbPut(db, cacheKey, compressedBlob);
          log(modName + ': cached compressed Blob (' + Math.round(compressedBlob.size / 1024 / 1024) + ' MB)');
        } catch (e) { log(modName + ': IDB put (compressed) failed: ' + e); }
      }
    }

    var tDecompress = (typeof performance !== 'undefined') ? performance.now() : 0;
    var raw2;
    try { raw2 = fzstd.decompress(compressed); }
    catch (e) { log(modName + ': decompress error: ' + e); return 0; }
    var tParse = (typeof performance !== 'undefined') ? performance.now() : 0;
    log(modName + ': decompressed ' + Math.round(raw2.length/1024/1024) + 'MB in ' + Math.round(tParse - tDecompress) + 'ms');

    var entries;
    try { entries = parseTar(raw2); }
    catch (e) { log(modName + ': tar parse error: ' + e); return 0; }
    var tWriteStart = (typeof performance !== 'undefined') ? performance.now() : 0;
    log(modName + ': parsed ' + entries.length + ' entries in ' + Math.round(tWriteStart - tParse) + 'ms');

    // (D) Save expanded cache.  Slice the entry list into three
    // parallel arrays so structured-clone only copies the JS
    // metadata (~hundreds of KB) and registers the Blob by
    // reference.
    if (db) {
      try {
        var names = new Array(entries.length);
        var offsets = new Uint32Array(entries.length);
        var lengths = new Uint32Array(entries.length);
        for (var ei = 0; ei < entries.length; ei++) {
          names[ei] = entries[ei].name;
          offsets[ei] = entries[ei].data.byteOffset - raw2.byteOffset;
          lengths[ei] = entries[ei].data.byteLength;
        }
        // raw2 wraps a buffer that may also hold tar padding past
        // the last entry; trim to (last offset + last length) to
        // keep the Blob compact.
        var lastEnd = entries.length > 0
          ? offsets[entries.length - 1] + lengths[entries.length - 1]
          : raw2.byteLength;
        var rawSlice = raw2.subarray(0, lastEnd);
        var rawBlob = new Blob([rawSlice]);
        await idbPut(db, expandedKey, {
          raw: rawBlob, names: names, offsets: offsets, lengths: lengths,
        });
        log(modName + ': cached expanded ('
          + Math.round(rawBlob.size/1024/1024) + ' MB blob + '
          + entries.length + ' entries)');
      } catch (e) { log(modName + ': IDB put (expanded) failed: ' + e); }
    }

    // Hand off to the same writer used by the expanded-cache path.
    var namesArr = new Array(entries.length);
    var offsetsArr = new Uint32Array(entries.length);
    var lengthsArr = new Uint32Array(entries.length);
    for (var ej = 0; ej < entries.length; ej++) {
      namesArr[ej] = entries[ej].name;
      offsetsArr[ej] = entries[ej].data.byteOffset - raw2.byteOffset;
      lengthsArr[ej] = entries[ej].data.byteLength;
    }
    return writeEntriesFromBuffer(modName, raw2, namesArr, offsetsArr, lengthsArr);
  }

  // VFS write path used by both cache hit and fresh-decompress.
  function writeEntriesFromBuffer(modName, raw, names, offsets, lengths) {
    var tWrite = (typeof performance !== 'undefined') ? performance.now() : 0;

    // ---- 4c. Write entries to MEMFS --------------------------------
    //
    // `FS.writeFile` allocates a fresh buffer for every entry and
    // memcpys data into it.  For 5000-7000 small files (one per
    // Std/Lean module) that loop dominated worker wall-clock —
    // 7+ seconds on a fast laptop, all of it busy inside one
    // microtask chain so the page sees no progress.
    //
    // `FS.createDataFile(parent, name, data, canRead, canWrite,
    //                    canOwn)` is the lower-level entry point.
    // The `canOwn` flag tells emscripten that we promise not to
    // mutate `data` afterwards, so MEMFS can keep a reference to
    // the same Uint8Array instead of copying.  For our case the
    // entries come from `parseTar(raw)` and `raw` is the
    // decompressed tarball that we hold for the duration of
    // loadModule(); after this we discard `raw` and the file
    // handles take ownership.
    //
    // Also do mkdir-once-per-prefix: previously every file walked
    // its full parent path through `mkdirP`, which mkdir'd the
    // same `/lib/lean/Std/Data/HashMap/` thousands of times.
    // Cache "we've already made this dir" across the loop.
    var madeDirs = Object.create(null);
    function ensureDir(path) {
      if (madeDirs[path]) return;
      var parts = path.split('/').filter(Boolean);
      var cur = '';
      for (var i = 0; i < parts.length; i++) {
        cur += '/' + parts[i];
        if (madeDirs[cur]) continue;
        try { FS.mkdir(cur); } catch (e) { /* exists */ }
        madeDirs[cur] = 1;
      }
    }

    var written = 0;
    var n = names.length;
    for (var k = 0; k < n; k++) {
      var name = names[k];
      if (!name) continue;
      var off = offsets[k];
      var len = lengths[k];
      var slash = name.lastIndexOf('/');
      var dir = slash > 0 ? '/lib/lean/' + name.substring(0, slash) : '/lib/lean';
      var base = slash > 0 ? name.substring(slash + 1) : name;
      ensureDir(dir);
      try {
        FS.createDataFile(dir, base, raw.subarray(off, off + len), true, false, true);
        written++;
      } catch (err) {
        // Likely EEXIST (a previous load wrote this path).  Skip.
      }
    }
    var tDone = (typeof performance !== 'undefined') ? performance.now() : 0;
    log(modName + ': VFS write ' + written + ' files in ' + Math.round(tDone - tWrite) + 'ms');
    log(modName + ': wrote ' + written + ' / ' + n + ' files to /lib/lean/');
    return written;
  }

  // ---- 5. Eagerly load every module in the manifest ---------------
  // Sequential, not parallel.  Earlier revs ran Promise.all over
  // every module to overlap fetch + decompress, but the peak
  // working-set under parallel load was several hundred MB of
  // tarball buffers + decompressed entries all live at once,
  // which OOMed the worker on Lean.  Doing them in series keeps
  // the high-water mark at "one module at a time" — Lean alone
  // (215 MB compressed → 1.3 GB decompressed) is already the
  // worst case.
  var modNames = Object.keys(MANIFEST.modules);
  var totalWritten = 0;
  for (var mi = 0; mi < modNames.length; mi++) {
    var mod = modNames[mi];
    try { totalWritten += await loadModule(mod, MANIFEST.modules[mod]); }
    catch (e) { log(mod + ': load threw: ' + e); }
  }
  log('done — ' + totalWritten + ' files written across ' + modNames.length + ' modules');
    Module.removeRunDependency(depTag);
  })().catch(function (err) {
    log('loadOleans crashed: ' + err);
    try { Module.removeRunDependency(depTag); } catch (_) {}
  });
});
