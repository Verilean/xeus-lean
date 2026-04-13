// getDylinkMetadata is only available with MAIN_MODULE (dynamic linking).
// We link statically, so it may not exist.
if (typeof getDylinkMetadata !== 'undefined') {
  Module['getDylinkMetadata'] = getDylinkMetadata;
}

// ---------------------------------------------------------------
// Dynamic .olean loading for Std/Lean/Sparkle modules.
//
// At this point (--post-js), the emscripten runtime and FS are
// fully initialized. Init .olean files are already in the VFS
// via --embed-file. We register Std/Lean/Sparkle .olean files
// as lazy files that are fetched on first read.
// ---------------------------------------------------------------
(function() {
  var OLEAN_BASE_URL = '';

  // Detect olean base URL by trying known candidates
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

  for (var i = 0; i < candidates.length; i++) {
    try {
      var xhr = new XMLHttpRequest();
      xhr.open('GET', candidates[i] + 'manifest.json', false);
      xhr.send();
      if (xhr.status === 200) {
        OLEAN_BASE_URL = candidates[i];
        break;
      }
    } catch(e) { /* try next */ }
  }

  if (!OLEAN_BASE_URL) {
    console.error('[WASM] No olean manifest found, Std/Lean/Sparkle unavailable');
    return;
  }

  // Load manifest and register lazy files in the VFS
  try {
    var xhr = new XMLHttpRequest();
    xhr.open('GET', OLEAN_BASE_URL + 'manifest.json', false);
    xhr.send();
    var manifest = JSON.parse(xhr.responseText);
    var count = 0;
    for (var i = 0; i < manifest.length; i++) {
      var relPath = manifest[i];
      var parts = relPath.split('/');

      // Ensure parent directories exist
      var dir = '/lib/lean';
      for (var j = 0; j < parts.length - 1; j++) {
        dir += '/' + parts[j];
        try { FS.mkdir(dir); } catch(e) { /* exists */ }
      }

      var fileName = parts[parts.length - 1];
      var fileUrl = OLEAN_BASE_URL + relPath;
      try {
        FS.createLazyFile(dir, fileName, fileUrl, true, false);
        count++;
      } catch(e) {
        // File may already exist (embedded Init/Display files)
      }
    }
    console.error('[WASM] Registered ' + count + ' lazy .olean files from ' + OLEAN_BASE_URL);
  } catch(e) {
    console.error('[WASM] Failed to load olean manifest: ' + e);
  }
})();
