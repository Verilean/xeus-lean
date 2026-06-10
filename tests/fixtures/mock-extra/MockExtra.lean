/-!
# MockExtra — reference fixture for xeus-lean's EXTRA_WASM_DIRS path

This is intentionally trivial: a single `@[extern]` declaration whose
implementation lives in `c_src/mock_extra_hello.c`.  It exercises:

- a `lake build` producing the olean tree
- a C extern that the WASM xlean kernel must resolve at link time
- the `xeus-lean-extra.json` manifest schema (written by
  `build-wasm.sh`)

If a downstream Lean library can plug into xlean the same way this
fixture does, the contract is satisfied.

The CI step `Build mock-extra fixture` builds this into a staging
directory and passes it via `-DEXTRA_WASM_DIRS=…`; `test_wasm_node`
then asserts that a Lean cell evaluating `MockExtra.mockHello ()`
returns the expected string.
-/

namespace MockExtra

/-- The greeting string the WASM test rig expects to see. -/
@[extern "mock_extra_hello"]
opaque mockHello : Unit → String

/-- Convenience wrapper so `IO.println (← MockExtra.greeting)` reads
    naturally inside a notebook cell. -/
def greeting : IO String :=
  pure (mockHello ())

end MockExtra
