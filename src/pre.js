Module.preRun = () => {
  // Configure Lean search path for WASM environment
  ENV.LEAN_PATH = "/lib/lean";
  ENV.LEAN_SYSROOT = "/";
};
