/-
Copyright (c) 2025, xeus-lean contributors
Released under Apache 2.0 license as described in the file LICENSE.

Lean REPL exports for the WASM xeus kernel.
These functions are called from C++ via @[export] attributes.
-/
import REPL.Main
import Lean.Data.Json

namespace WasmRepl

open REPL Lean

/-- Global REPL state reference, created once and reused across calls. -/
private def mkInitialState : REPL.State :=
  { cmdStates := #[], proofStates := #[] }

/-- Initialize the Lean search path and runtime.
    In WASM, .olean files are embedded at /lib/lean/ in the virtual filesystem,
    so the sysroot is "/" (initSearchPath looks for <sysroot>/lib/lean/).
    We avoid Lean.findSysroot which spawns `lean --print-prefix` (impossible in WASM). -/
@[export lean_wasm_repl_init]
def init : IO Unit := do
  Lean.initSearchPath "/"

/-- Create a new REPL state reference (IO.Ref State). -/
@[export lean_wasm_repl_create_state]
def createState : IO (IO.Ref REPL.State) :=
  IO.mkRef mkInitialState

/-- Execute a command via the REPL and return the result as a JSON string.

    Parameters:
    - stateRef: mutable reference to the REPL state
    - code: the Lean code to execute
    - envId: environment ID to use (from a previous execution)
    - hasEnv: 1 if envId should be used, 0 for fresh environment
    Returns: JSON string with the result
-/
@[export lean_wasm_repl_execute]
def execute (stateRef : IO.Ref REPL.State) (code : String) (envId : UInt32) (hasEnv : UInt8) : IO String := do
  IO.eprintln s!"[WasmRepl] execute: code='{code.take 50}' envId={envId} hasEnv={hasEnv}"
  let env : Option Nat := if hasEnv.toNat == 1 then some envId.toNat else none

  let cmd : REPL.Command := {
    cmd := code,
    env := env,
    infotree := none,
    allTactics := none,
    rootGoals := none
  }

  IO.eprintln s!"[WasmRepl] calling runCommand (env={env})"
  let state ← stateRef.get
  let result ← runCommand cmd |>.run state
  IO.eprintln "[WasmRepl] runCommand returned"

  match result with
  | (.inl response, newState) =>
    stateRef.set newState
    let json := Lean.toJson response
    IO.eprintln s!"[WasmRepl] success (full): {json.pretty}"
    let jsonStr := json.compress
    return jsonStr
  | (.inr error, newState) =>
    stateRef.set newState
    let json := Lean.toJson error |>.compress
    IO.eprintln s!"[WasmRepl] error: {json.take 200}"
    return json

end WasmRepl
