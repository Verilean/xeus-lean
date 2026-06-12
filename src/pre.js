// Minimal pre.js: just set env vars.
// Dynamic .olean loading also runs in preRun (registered from post.js).
Module.preRun = Module.preRun || [];
Module.preRun.push(() => {
  ENV.LEAN_PATH = "/lib/lean";
  ENV.LEAN_SYSROOT = "/";
});

// Capture WASM stdout so xinterpreter_wasm.cpp can drain it at the
// end of each execute_request and route it through the same MIME /
// publish pipeline the native kernel uses.  Without this hook
// emscripten's default `Module.print` would route IO.println straight
// to console.log — invisible to the notebook cell.
//
// This is the WASM analogue of `xeus_ffi.cpp`'s dup2-based fd-1 pipe.
// See https://github.com/Verilean/xeus-lean/issues/11.
//
// stderr is treated differently: most of what the runtime writes to
// it is `[WasmRepl] …` / `[WASM] …` instrumentation that's only
// useful in the DevTools console.  Capturing it like stdout would
// flood every cell's output area and drown out the rich-display
// payload that arrives a frame later — empirically that broke the
// Playwright `#svg embeds an SVG` test even though the SVG payload
// itself was emitted correctly.  Tag a line with the MIME envelope
// (Display.* / `#showVerilog` etc.) if you genuinely need it in the
// notebook cell; everything else goes to console.error so it stays
// visible to a developer without leaking into user-visible output.
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
  if (text && text.indexOf('\x1bMIME:') !== -1) {
    Module._xleanStderrBuf += text + '\n';
  } else {
    if (typeof console !== 'undefined' && console.error) {
      console.error(text);
    }
  }
};
