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

  function log(msg) { try { console.error('[olean] ' + msg); } catch(_) {} }

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

  // ---- 4. Fetch + extract one tarball into /lib/lean/ -------------
  async function loadModule(modName, info) {
    var url = ASSET_BASE + info.asset;
    log('fetching ' + url + ' (' + Math.round(info.size / 1024 / 1024) + ' MB compressed, ' + info.files + ' files)');

    var compressed;
    try {
      var resp = await fetch(url);
      if (!resp.ok) { log(modName + ': fetch failed status=' + resp.status); return 0; }
      var ab = await resp.arrayBuffer();
      compressed = new Uint8Array(ab);
    } catch (e) { log(modName + ': fetch error: ' + e); return 0; }

    var raw;
    try { raw = fzstd.decompress(compressed); }
    catch (e) { log(modName + ': decompress error: ' + e); return 0; }

    var entries;
    try { entries = parseTar(raw); }
    catch (e) { log(modName + ': tar parse error: ' + e); return 0; }

    var written = 0;
    for (var k = 0; k < entries.length; k++) {
      var e = entries[k];
      if (!e.name) continue;
      var vfsPath = '/lib/lean/' + e.name;
      var slash = vfsPath.lastIndexOf('/');
      if (slash > 0) mkdirP(vfsPath.substring(0, slash));
      try {
        try { FS.stat(vfsPath); continue; } catch (_) {}
        FS.writeFile(vfsPath, e.data);
        written++;
      } catch (_) { /* per-file failure is non-fatal */ }
    }
    log(modName + ': wrote ' + written + ' / ' + entries.length + ' files to /lib/lean/');
    return written;
  }

  // ---- 5. Eagerly load every module in the manifest ---------------
  var totalWritten = 0;
  for (var mod in MANIFEST.modules) {
    if (Object.prototype.hasOwnProperty.call(MANIFEST.modules, mod)) {
      try { totalWritten += await loadModule(mod, MANIFEST.modules[mod]); }
      catch(e) { log(mod + ': load threw: ' + e); }
    }
  }
  log('done — ' + totalWritten + ' files written across ' + Object.keys(MANIFEST.modules).length + ' modules');
    Module.removeRunDependency(depTag);
  })().catch(function (err) {
    log('loadOleans crashed: ' + err);
    try { Module.removeRunDependency(depTag); } catch (_) {}
  });
});
