-- WASM-only Lake build override for the hesper submodule.
--
-- Drops upstream's LSpec dependency, the native-deps trigger, and the
-- Tests / Examples libraries. The WASM REPL only needs the compiled
-- `Hesper` Lean library (and not even all of it — Phase 1 needs just
-- WGSL; later phases will pull in more).
--
-- This file is COPIED into the hesper submodule by build-wasm.sh just
-- before `lake build`. The original lakefile.lean / lakefile.toml are
-- preserved on disk and restored after the build.

import Lake
open Lake DSL

package «Hesper» where

lean_lib «Hesper» where
  globs := #[.submodules `Hesper]

-- We want to expose the lib only — no executables on WASM.
