// Dynamic .olean loading for Std/Lean/Sparkle modules.
//
// Init .olean files are embedded via --embed-file. Std/Lean/Sparkle
// are served as static assets and loaded into the VFS on demand via
// FS.createLazyFile (synchronous XHR on first access).

var OLEAN_BASE_URL = '';

Module.preRun = Module.preRun || [];
Module.preRun.push(() => {
  ENV.LEAN_PATH = "/lib/lean";
  ENV.LEAN_SYSROOT = "/";

  // Detect olean base URL. In JupyterLite, xlean.js runs via the
  // xeus-extension worker. The olean assets are at a known path
  // relative to the site root: /xeus/wasm-host/olean/
  // We try multiple strategies to find the right URL.
  var candidates = [];

  // Strategy 1: relative to scriptDirectory (may point to extensions/)
  if (typeof scriptDirectory !== 'undefined' && scriptDirectory) {
    // scriptDirectory = ".../extensions/@jupyterlite/xeus-extension/static/"
    // or ".../xeus/wasm-host/bin/"
    // Try going to site root and then xeus/wasm-host/olean/
    var parts = scriptDirectory.split('/');
    // Find "xeus" in path to determine site root
    var xeusIdx = parts.indexOf('xeus');
    if (xeusIdx >= 0) {
      var siteRoot = parts.slice(0, xeusIdx).join('/') + '/';
      candidates.push(siteRoot + 'xeus/wasm-host/olean/');
    }
    // Also try relative to bin/
    candidates.push(scriptDirectory + '../olean/');
  }

  // Strategy 2: from document.baseURI or location (not available in worker)
  // Strategy 3: hardcoded fallback
  candidates.push('/xeus/wasm-host/olean/');
  candidates.push('./olean/');

  // Try each candidate to find manifest.json
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
    console.error('[WASM] Could not find olean manifest at any candidate URL');
    console.error('[WASM] Tried: ' + candidates.join(', '));
    return;
  }

  // Load manifest and register lazy files
  try {
    var xhr = new XMLHttpRequest();
    xhr.open('GET', OLEAN_BASE_URL + 'manifest.json', false);
    xhr.send();
    var manifest = JSON.parse(xhr.responseText);
    var count = 0;
    for (var i = 0; i < manifest.length; i++) {
      var relPath = manifest[i];
      var parts = relPath.split('/');
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
      } catch(e) { /* already exists (embedded Init) */ }
    }
    console.error('[WASM] Registered ' + count + ' lazy .olean files from ' + OLEAN_BASE_URL);
  } catch(e) {
    console.error('[WASM] Failed to load olean manifest: ' + e);
  }
});
