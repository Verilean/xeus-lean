// Resolve paths for --preload-file .data files. In JupyterLite,
// xlean.js runs inside a Web Worker where the default locateFile
// may not find xlean.data. We ensure it looks in the same directory
// as xlean.js itself.
if (typeof Module.locateFile === 'undefined') {
  Module.locateFile = (path) => {
    if (typeof scriptDirectory !== 'undefined' && scriptDirectory) {
      return scriptDirectory + path;
    }
    return path;
  };
}

Module.preRun = () => {
  // Configure Lean search path for WASM environment
  ENV.LEAN_PATH = "/lib/lean";
  ENV.LEAN_SYSROOT = "/";
};
