/-
Copyright (c) 2025, xeus-lean contributors
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Lean

namespace LeanKernel

open Lean Elab

/-- State maintained across REPL interactions -/
structure State where
  env : Environment
  msgLog : MessageLog := {}

/-- Initialize the kernel with basic imports -/
def initializeState : IO State := do
  let env ← importModules #[] {} 0
  return { env := env }

/-- Execute Lean code and return result -/
def executeCode (state : State) (code : String) : IO (State × String) := do
  let inputCtx := Parser.mkInputContext code "<input>"

  try
    -- Create a simple command state
    let cmdCtx : Command.Context := {
      fileName := "<input>"
      fileMap := default
      tacticCache? := none
      snap? := none
      cancelTk? := none
    }

    let cmdState : Command.State := {
      env := state.env
      messages := state.msgLog
      infoState := { enabled := false }
    }

    -- Try to parse and elaborate the code
    let (cmds, _) := Parser.parseCommands inputCtx "" .nil

    -- Process commands
    let mut newState := cmdState
    for cmd in cmds do
      let (_, st) ← (elabCommand cmd).run cmdCtx newState
      newState := st

    -- Collect messages
    let output := newState.messages.toList.foldl (fun acc msg =>
      acc ++ msg.data.toString ++ "\n"
    ) ""

    return ({ env := newState.env, msgLog := newState.messages }, output)
  catch e =>
    return (state, s!"Error: {e}")

end LeanKernel
