// Minimal pre.js: just set env vars.
// Dynamic .olean loading also runs in preRun (registered from post.js).
Module.preRun = Module.preRun || [];
Module.preRun.push(() => {
  ENV.LEAN_PATH = "/lib/lean";
  ENV.LEAN_SYSROOT = "/";
});
