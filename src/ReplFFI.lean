/-
Copyright (c) 2025, xeus-lean contributors
Released under Apache 2.0 license as described in the file LICENSE.
-/
import REPL.Main
import Lean.Data.Json

namespace ReplFFI

open REPL Lean

/-- Opaque handle for the REPL state -/
structure ReplHandle where
  stateRef : IO.Ref State

/-- Initialize a new REPL context -/
@[export lean_repl_init]
def replInit : IO (Option ReplHandle) := do
  try
    let initialState : State := { cmdStates := #[], proofStates := #[] }
    let stateRef ← IO.mkRef initialState
    return some { stateRef := stateRef }
  catch _ =>
    return none

/-- Execute a command -/
@[export lean_repl_execute_cmd]
def replExecute (handle : ReplHandle) (cmdJson : String) : IO String := do
  try
    -- Parse the JSON input
    let json := Json.parse cmdJson
    match json with
    | .error e => return Json.mkObj [("error", Json.str s!"JSON parse error: {e}")] |>.compress
    | .ok j =>
      match fromJson? j with
      | .error e => return Json.mkObj [("error", Json.str s!"Invalid command format: {e}")] |>.compress
      | .ok (cmd : REPL.Command) =>
        let state ← handle.stateRef.get
        let result ← runCommand cmd |>.run state
        match result with
        | (.inl response, newState) =>
          handle.stateRef.set newState
          return Lean.toJson response |>.compress
        | (.inr error, newState) =>
          handle.stateRef.set newState
          return Lean.toJson error |>.compress
  catch e =>
    return Json.mkObj [("error", Json.str e.toString)] |>.compress

/-- Free the REPL context -/
@[export lean_repl_free]
def replFree (_ : ReplHandle) : IO Unit := do
  return ()

end ReplFFI
