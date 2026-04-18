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
// At --post-js time the emscripten runtime + FS are ready and Init/
// Display are already in the VFS via --embed-file. We download
// manifest-v2.json, then for each module fetch <baseUrl><asset>,
// decompress (zstd → tar), and FS.writeFile each entry under
// /lib/lean/.
//
// Failures here are logged but never throw — a kernel that boots
// without Std/Lean/Sparkle/Hesper is still useful for Init-only code.
// ---------------------------------------------------------------
(function() {
  'use strict';

  function log(msg) { try { console.error('[olean] ' + msg); } catch(_) {} }

  if (typeof XMLHttpRequest === 'undefined') {
    log('XMLHttpRequest unavailable — skipping dynamic olean load');
    return;
  }

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
        try {
          MANIFEST = JSON.parse(xhr.responseText);
          BASE = candidates[i];
          log('manifest-v2 found at ' + BASE);
          break;
        } catch(parseErr) {
          log('manifest-v2 at ' + candidates[i] + ' did not parse: ' + parseErr);
        }
      }
    } catch(e) { /* try next */ }
  }
  if (!MANIFEST) { log('no manifest-v2.json — only embedded modules will work'); return; }

  if (typeof fzstd === 'undefined' || typeof fzstd.decompress !== 'function') {
    log('fzstd not loaded — cannot decompress tarballs (skipping)');
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
  function loadModuleSync(modName, info) {
    var url = ASSET_BASE + info.asset;
    log('fetching ' + url + ' (' + Math.round(info.size / 1024 / 1024) + ' MB compressed, ' + info.files + ' files)');

    var compressed;
    try {
      var xhr = new XMLHttpRequest();
      xhr.open('GET', url, false);
      xhr.responseType = 'arraybuffer';
      xhr.send();
      if (xhr.status !== 200) { log(modName + ': fetch failed status=' + xhr.status); return 0; }
      compressed = new Uint8Array(xhr.response);
    } catch(e) { log(modName + ': fetch error: ' + e); return 0; }

    var raw;
    try { raw = fzstd.decompress(compressed); }
    catch(e) { log(modName + ': decompress error: ' + e); return 0; }

    var entries;
    try { entries = parseTar(raw); }
    catch(e) { log(modName + ': tar parse error: ' + e); return 0; }

    var written = 0;
    for (var k = 0; k < entries.length; k++) {
      var e = entries[k];
      if (!e.name) continue;
      var vfsPath = '/lib/lean/' + e.name;
      var slash = vfsPath.lastIndexOf('/');
      if (slash > 0) mkdirP(vfsPath.substring(0, slash));
      try {
        try { FS.stat(vfsPath); continue; } catch(_) {}
        FS.writeFile(vfsPath, e.data);
        written++;
      } catch(_) { /* per-file failure is non-fatal */ }
    }
    log(modName + ': wrote ' + written + ' / ' + entries.length + ' files to /lib/lean/');
    return written;
  }

  // ---- 5. Eagerly load every module in the manifest ---------------
  var totalWritten = 0;
  for (var mod in MANIFEST.modules) {
    if (Object.prototype.hasOwnProperty.call(MANIFEST.modules, mod)) {
      try { totalWritten += loadModuleSync(mod, MANIFEST.modules[mod]); }
      catch(e) { log(mod + ': load threw: ' + e); }
    }
  }
  log('done — ' + totalWritten + ' files written across ' + Object.keys(MANIFEST.modules).length + ' modules');
})();
