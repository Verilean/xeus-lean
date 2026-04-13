// Minimal pre.js: just set env vars.
// Dynamic .olean loading is done in post.js where FS is ready.
Module.preRun = Module.preRun || [];
Module.preRun.push(() => {
  ENV.LEAN_PATH = "/lib/lean";
  ENV.LEAN_SYSROOT = "/";
});
