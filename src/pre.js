// Minimal pre.js: just set env vars.
// Dynamic .olean loading also runs in preRun (registered from post.js).
Module.preRun = Module.preRun || [];
Module.preRun.push(() => {
  ENV.LEAN_PATH = "/lib/lean";
  ENV.LEAN_SYSROOT = "/";
});

// Capture WASM stdout / stderr so xinterpreter_wasm.cpp can drain
// them at the end of each execute_request and route them through the
// same MIME / publish pipeline the native kernel uses.  Without this
// hook emscripten's default `Module.print` would route IO.println
// straight to console.log — invisible to the notebook cell.
//
// This is the WASM analogue of `xeus_ffi.cpp`'s dup2-based fd-1
// pipe.  See https://github.com/Verilean/xeus-lean/issues/11.
Module._xleanStdoutBuf = '';
Module._xleanStderrBuf = '';
Module.print = function (text) {
  if (arguments.length > 1) {
    text = Array.prototype.slice.call(arguments).join(' ');
  }
  Module._xleanStdoutBuf += text + '\n';
};
Module.printErr = function (text) {
  if (arguments.length > 1) {
    text = Array.prototype.slice.call(arguments).join(' ');
  }
  Module._xleanStderrBuf += text + '\n';
};
