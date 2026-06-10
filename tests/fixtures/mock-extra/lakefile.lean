import Lake
open Lake DSL

-- Minimal lake project that produces a single `MockExtra.olean`.
-- The matching native library (libmock_extra_wasm.a or the .so on
-- native) is built outside lake by `build-wasm.sh` / `build-native.sh`
-- using emcc / clang directly.  Lake's own native-library support
-- is fine but pulls in more infrastructure than this fixture needs.

package mockExtra where
  -- We don't ship `precompileModules` because there are no Lean-side
  -- C bindings to compile; the lone extern is implemented in C.

lean_lib MockExtra where
  -- The single-file lib whose top-level module name is "MockExtra".
  -- Whatever name appears here must match `olean_root` in the
  -- xeus-lean-extra.json the build script writes.
  roots := #[`MockExtra]
