/-
Copyright (c) 2025, xeus-lean contributors
Released under Apache 2.0 license as described in the file LICENSE.

Lean REPL exports for the WASM xeus kernel.
These functions are called from C++ via @[export] attributes.
-/
import REPL.Main
import Lean.Data.Json
-- Import Display so that #html / #latex / #md / #svg commands and the
-- Display.html / Display.latex / ... helpers are available in REPL cells
-- without an explicit import.
import Display

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

  -- Drain the Display buffer. Display.html/latex/... append MIME
  -- markers to a global IO.Ref rather than printing to stdout,
  -- because Lean 4.28's #eval stdout capture (withIsolatedStreams)
  -- does not work in WASM.
  let displayOutput ← Display.drain
  IO.eprintln s!"[WasmRepl] displayOutput='{displayOutput.take 200}' len={displayOutput.length}"

  match result with
  | (.inl response, newState) =>
    stateRef.set newState
    -- If there was rich-display output, inject it as an additional
    -- info message. The C++ interpreter will parse MIME markers out.
    -- Use the raw string as message data (don't trim) to preserve
    -- ESC (0x1B) sentinels in MIME markers.
    let response := if displayOutput.isEmpty then response
      else
        let displayMsg : REPL.Message := {
          pos := ⟨0, 0⟩
          endPos := none
          severity := .info
          data := displayOutput
        }
        { response with messages := response.messages ++ [displayMsg] }
    let json := Lean.toJson response
    IO.eprintln s!"[WasmRepl] success (full): {json.pretty}"
    let jsonStr := json.compress
    return jsonStr
  | (.inr error, newState) =>
    stateRef.set newState
    let json := Lean.toJson error |>.compress
    IO.eprintln s!"[WasmRepl] error: {json.take 200}"
    return json

/-- Return tab-completion candidates as a JSON string.

    Parameters:
    - stateRef: mutable reference to the REPL state
    - prefix: the text before the cursor to complete
    - envId: environment ID to look up constants in
    - hasEnv: 1 if envId should be used, 0 to use the latest
    Returns: JSON string `{"matches":["List.map","List.filter",...]}`
-/
@[export lean_wasm_repl_complete]
def complete (stateRef : IO.Ref REPL.State) (pfx : String) (envId : UInt32) (hasEnv : UInt8) : IO String := do
  let state ← stateRef.get
  -- Resolve environment: use specified envId or the latest one
  let envIdx := if hasEnv.toNat == 1 then envId.toNat
    else if state.cmdStates.size > 0 then state.cmdStates.size - 1
    else 0
  let env? := (state.cmdStates[envIdx]?).map (·.cmdState.env)
  -- Keywords and # commands to always suggest
  let keywords : Array String := #["def", "theorem", "lemma", "example",
    "structure", "class", "instance", "where", "let", "have", "do",
    "if", "then", "else", "match", "with", "import", "open",
    "namespace", "section", "end", "variable", "noncomputable",
    "private", "protected", "partial", "unsafe", "macro", "syntax",
    "inductive", "abbrev", "opaque", "axiom",
    "#eval", "#check", "#print", "#reduce",
    "#html", "#latex", "#md", "#svg", "#json"]
  let kwMatches := keywords.filter fun kw => kw.startsWith pfx
  -- If we have an environment, search its constants too
  let envMatches : Array String := match env? with
    | none => #[]
    | some env =>
      env.constants.fold (init := #[]) fun acc name _info =>
        if acc.size < 200 then
          let nameStr := name.toString
          if nameStr.startsWith pfx then acc.push nameStr
          else acc
        else acc
  -- Combine, deduplicate, limit to 50
  let allMatches := (kwMatches ++ envMatches).toList.eraseDups
  let limited := allMatches.take 50
  let json := Lean.Json.mkObj [("matches", Lean.toJson limited.toArray)]
  return json.compress

end WasmRepl
