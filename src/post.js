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

    // Browsers that support DecompressionStream('zstd') (Chrome
    // 123+, Edge, etc.) hand decompression off to the native zstd
    // implementation — ~5x faster than fzstd's pure-JS port on
    // typical Lean tarballs.  fzstd stays as a fallback for older
    // browsers and Firefox until it ships zstd support.
    var hasNativeZstd = false;
    try {
      if (typeof DecompressionStream === 'function') {
        // Construct one to verify 'zstd' is in the supported format
        // list; older browsers throw TypeError for unknown formats.
        new DecompressionStream('zstd');
        hasNativeZstd = true;
      }
    } catch (_) { hasNativeZstd = false; }

    var hasFzstd = typeof fzstd !== 'undefined' && typeof fzstd.decompress === 'function';
    if (!hasNativeZstd && !hasFzstd) {
      log('no zstd decoder available (no DecompressionStream and no fzstd) — skipping');
      Module.removeRunDependency(depTag);
      return;
    }
    log('zstd decoder: ' + (hasNativeZstd ? 'native DecompressionStream' : 'fzstd (pure JS)'));

    async function decompressZstd(compressed) {
      if (hasNativeZstd) {
        var ds = new DecompressionStream('zstd');
        var resp = new Response(new Blob([compressed]).stream().pipeThrough(ds));
        var ab = await resp.arrayBuffer();
        return new Uint8Array(ab);
      }
      return fzstd.decompress(compressed);
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
  //   network fetch (HTTPS) → zstd decompress → parseTar → write
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
      tx.objectStore(STORE).put(val, key);
      // Resolve on tx.oncomplete, not request.onsuccess: the put
      // request fires before the transaction commits, so a quick
      // page close after `await idbPut(...)` returned could still
      // lose the write.  Waiting for tx.oncomplete guarantees the
      // bytes are on disk (or at least committed to the IDB
      // backing store) before we return.
      tx.oncomplete = function () { resolve(); };
      tx.onerror    = function () { reject(tx.error); };
      tx.onabort    = function () { reject(tx.error); };
    });
  }

  var dbPromise = openDB().catch(function () { return null; });

  // ---- 4b. Fetch + extract one tarball into /lib/lean/ ------------
  //
  // Two cache levels.  The "expanded" cache stores the post-
  // decompress / post-parseTar state — a Blob of the raw tar bytes
  // plus a compact { names, offsets, lengths } index — keyed under
  //   modName|asset|size|EXPANDED-V1
  // On hit we skip both zstd decompress (≈9 s for Lean) and tar
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
        if (cached) {
          var okRaw = cached.raw instanceof Blob;
          var okNames = Array.isArray(cached.names);
          var okOff = cached.offsets instanceof Uint32Array;
          var okLen = cached.lengths instanceof Uint32Array;
          var okLenMatch = okNames && okOff && cached.names.length === cached.offsets.length;
          if (okRaw && okNames && okOff && okLen && okLenMatch) {
            var tHit = (typeof performance !== 'undefined') ? performance.now() : 0;
            var ab = await cached.raw.arrayBuffer();
            var raw = new Uint8Array(ab);
            var tWrite = (typeof performance !== 'undefined') ? performance.now() : 0;
            log(modName + ': expanded-cache hit, ' + Math.round(raw.length/1024/1024) + 'MB Blob → AB in ' + Math.round(tWrite - tHit) + 'ms');
            return writeEntriesFromBuffer(modName, raw, cached.names, cached.offsets, cached.lengths);
          } else {
            log(modName + ': expanded-cache shape mismatch raw=' + okRaw + ' names=' + okNames + ' off=' + okOff + ' len=' + okLen + ' match=' + okLenMatch);
          }
        }
      } catch (e) { log(modName + ': expanded-cache read error: ' + e); }
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
      } catch (e) { log(modName + ': compressed-cache read error: ' + e); }
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

      // Note: we used to write the compressed tarball to IDB here,
      // but the expanded cache (see (D) below) supersedes it on warm
      // boot — the only path that ever reads the compressed cache
      // is a partial migration from an older xeus-lean build, which
      // we don't need to optimize.  Skipping the put saves ~3 s of
      // cold-boot wall clock (one ~200 MB Blob commit per module).
    }

    var tDecompress = (typeof performance !== 'undefined') ? performance.now() : 0;
    var raw2;
    try { raw2 = await decompressZstd(compressed); }
    catch (e) { log(modName + ': decompress error: ' + e); return 0; }
    var tParse = (typeof performance !== 'undefined') ? performance.now() : 0;
    log(modName + ': decompressed ' + Math.round(raw2.length/1024/1024) + 'MB in ' + Math.round(tParse - tDecompress) + 'ms');

    var entries;
    try { entries = parseTar(raw2); }
    catch (e) { log(modName + ': tar parse error: ' + e); return 0; }
    var tWriteStart = (typeof performance !== 'undefined') ? performance.now() : 0;
    log(modName + ': parsed ' + entries.length + ' entries in ' + Math.round(tWriteStart - tParse) + 'ms');

    // Build the parallel-array form once — both the VFS write and
    // the (deferred) expanded-cache write consume it.
    var namesArr = new Array(entries.length);
    var offsetsArr = new Uint32Array(entries.length);
    var lengthsArr = new Uint32Array(entries.length);
    for (var ei = 0; ei < entries.length; ei++) {
      namesArr[ei] = entries[ei].name;
      offsetsArr[ei] = entries[ei].data.byteOffset - raw2.byteOffset;
      lengthsArr[ei] = entries[ei].data.byteLength;
    }

    // (D) Save expanded cache.
    //
    // Default mode (startup loader for Init/Std/Lean/Sparkle):
    // fire-and-forget via queueMicrotask, so the VFS write below
    // doesn't block on the IDB commit.  Cold boot finishes faster;
    // the put settles in background.
    //
    // Sync mode (Module._xleanSyncExpandedCache, set by
    // loadManifestAsync for %load mathlib): await the put before
    // returning.  Mathlib is 32+ chunks back-to-back; firing all
    // of them in microtasks pins 32 Blobs in worker memory until
    // they all commit, which blows past Chrome's ~3.76 GB jsHeap-
    // SizeLimit at chunk ~18.  Awaiting per chunk means at most one
    // Blob is resident at a time and the next fetch can allocate.
    if (db) {
      var lastEnd = entries.length > 0
        ? offsetsArr[entries.length - 1] + lengthsArr[entries.length - 1]
        : raw2.byteLength;
      var rawBlob = new Blob([raw2.subarray(0, lastEnd)]);
      var cacheEntry = {
        raw: rawBlob,
        names: namesArr,
        offsets: offsetsArr,
        lengths: lengthsArr,
      };
      if (Module._xleanSyncExpandedCache) {
        try {
          await idbPut(db, expandedKey, cacheEntry);
          log(modName + ': cached expanded ('
            + Math.round(rawBlob.size/1024/1024) + ' MB blob + '
            + entries.length + ' entries)');
        } catch (e) {
          log(modName + ': IDB put (expanded, sync) failed: ' + e);
        }
        // Drop our local strong refs so the Blob/sidecar can be
        // collected before the next chunk's fetch+decompress.
        rawBlob = null;
        cacheEntry = null;
      } else {
        queueMicrotask(function () {
          idbPut(db, expandedKey, cacheEntry).then(function () {
            log(modName + ': cached expanded ('
              + Math.round(rawBlob.size/1024/1024) + ' MB blob + '
              + entries.length + ' entries)');
          }, function (e) {
            log(modName + ': IDB put (expanded) failed: ' + e);
          });
        });
      }
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

  // ---- 6. Expose a runtime loader for extra manifests -------------
  //
  // Used by `%load <name>` cell magic.  The startup loader above
  // pulled `manifest-v2.json` (Init/Std/Lean/Sparkle) from the
  // resolved BASE; additional bundles (Mathlib, etc.) live next to
  // it as `manifest-<name>.json` and are loaded on demand.
  //
  // Resolution rule: if `manifestUrl` is absolute (starts with
  // http:// or https:// or /), use it as-is.  Otherwise treat it
  // as a manifest *name* (e.g. "mathlib") and fetch
  // `<BASE>manifest-<name>.json`.
  //
  // opts.onProgress(stage, info) is called between stages so callers
  // (the cell magic, ultimately) can stream a human-readable log.
  Module.loadManifestAsync = async function (manifestUrl, opts) {
    opts = opts || {};
    var onProgress = opts.onProgress || function () {};
    // Use sync expanded-cache writes for this load: see (D) above
    // in loadModule().  Mathlib's 32 chunks back-to-back overrun the
    // worker's jsHeapSizeLimit if we keep all the in-flight Blobs
    // pinned via queueMicrotask, so we commit each chunk to IDB and
    // release its Blob ref before starting the next fetch.
    Module._xleanSyncExpandedCache = true;
    var url, baseForAssets;
    if (/^(https?:)?\/\//.test(manifestUrl) || manifestUrl.startsWith('/')) {
      url = manifestUrl;
      var slash = url.lastIndexOf('/');
      baseForAssets = slash >= 0 ? url.substring(0, slash + 1) : BASE;
    } else {
      url = BASE + 'manifest-' + manifestUrl + '.json';
      baseForAssets = BASE;
    }
    onProgress('fetching-manifest', { url: url });
    var resp = await fetch(url);
    if (!resp.ok) throw new Error('manifest fetch failed: ' + resp.status + ' ' + url);
    var manifest = await resp.json();
    var mods = manifest.modules || {};
    var names = Object.keys(mods);
    var assetBase = manifest.baseUrl || baseForAssets;
    var written = 0;
    for (var ni = 0; ni < names.length; ni++) {
      var name = names[ni];
      onProgress('loading-module', {
        name: name, index: ni, total: names.length, info: mods[name],
      });
      // loadModule() reads ASSET_BASE from its enclosing scope, which
      // points at the startup manifest's location.  For an on-demand
      // load we may need a different base, so swap it for the call
      // and restore after.  This is a small wart; refactoring
      // loadModule() to take base as a parameter would be cleaner
      // but requires touching more code paths.
      var prev = ASSET_BASE;
      ASSET_BASE = assetBase;
      try {
        written += await loadModule(name, mods[name]);
      } finally {
        ASSET_BASE = prev;
      }
    }
    onProgress('done', { written: written, modules: names.length });
    Module._xleanSyncExpandedCache = false;
    return { written: written, modules: names };
  };

    Module.removeRunDependency(depTag);
  })().catch(function (err) {
    log('loadOleans crashed: ' + err);
    try { Module.removeRunDependency(depTag); } catch (_) {}
  });
});
