/-
Copyright (c) 2025, xeus-lean contributors
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Lean

namespace LeanRepl.FFI

open Lean Elab Command

/-- Context for the REPL session -/
structure ReplContext where
  env : Environment
  cmdState : Command.State
  messages : Array String := #[]

/-- Initialize a new REPL context -/
@[export lean_repl_init]
def initialize : IO ReplContext := do
  let env ← importModules #[] {} 0
  let cmdState : Command.State := {
    env := env
    messages := {}
    infoState := {}
  }
  return { env := env, cmdState := cmdState }

/-- Execute a command and return the result -/
def executeCommand (ctx : ReplContext) (code : String) : IO (ReplContext × String × String) := do
  try
    let inputCtx := Parser.mkInputContext code "<input>"
    let (header, parserState, messages) ← Parser.parseHeader inputCtx

    let (env, msgs) ← processHeader header {} messages inputCtx

    let cmdState : Command.State := {
      ctx.cmdState with
      env := env
      messages := msgs
    }

    -- Parse and process the command
    let s := parserState.toStringPos
    let cmdParser := Parser.commandParser
    let (cmd, _) := cmdParser.run inputCtx { toStringPos := s }

    -- Process the command
    let mut output := ""
    let mut errors := ""

    for msg in msgs.toList do
      match msg.severity with
      | MessageSeverity.error => errors := errors ++ msg.data.toString ++ "\n"
      | _ => output := output ++ msg.data.toString ++ "\n"

    let newCtx := { ctx with cmdState := cmdState, env := env }
    return (newCtx, output, errors)
  catch e =>
    return (ctx, "", e.toString)

/-- C FFI exports -/

/-- Opaque handle for C -/
structure ReplHandle where
  ref : IO.Ref ReplContext

@[export lean_repl_new]
def replNew : IO USize := do
  let ctx ← initialize
  let ref ← IO.mkRef ctx
  let handle := ReplHandle.mk ref
  return unsafeCast handle

@[export lean_repl_free]
def replFree (handle : USize) : IO Unit := do
  -- Nothing to free explicitly in Lean's GC
  return ()

@[export lean_repl_execute]
def replExecute (handle : USize) (codePtr : USize) (codeLen : USize) : IO (USize × USize × USize) := do
  let handle : ReplHandle := unsafeCast handle
  let code := String.fromUTF8Unchecked (ByteArray.copySlice (ByteArray.mkEmpty codeLen) 0 ⟨unsafeCast codePtr⟩ 0 codeLen)

  let ctx ← handle.ref.get
  let (newCtx, output, errors) ← executeCommand ctx code
  handle.ref.set newCtx

  -- Return pointers to strings
  let outputPtr := unsafeCast output.toUTF8
  let errorsPtr := unsafeCast errors.toUTF8
  let success := if errors.isEmpty then 1 else 0

  return (success, outputPtr, errorsPtr)

@[export lean_repl_is_complete]
def replIsComplete (handle : USize) (codePtr : USize) (codeLen : USize) : IO USize := do
  let code := String.fromUTF8Unchecked (ByteArray.copySlice (ByteArray.mkEmpty codeLen) 0 ⟨unsafeCast codePtr⟩ 0 codeLen)

  -- Simple heuristic: check for balanced delimiters
  let openCount := code.foldl (fun acc c => if c = '(' || c = '{' || c = '[' then acc + 1 else acc) 0
  let closeCount := code.foldl (fun acc c => if c = ')' || c = '}' || c = ']' then acc + 1 else acc) 0

  if openCount > closeCount then
    return unsafeCast "incomplete"
  else
    return unsafeCast "complete"

@[export lean_repl_check]
def replCheck (handle : USize) (identPtr : USize) (identLen : USize) : IO USize := do
  let handle : ReplHandle := unsafeCast handle
  let ident := String.fromUTF8Unchecked (ByteArray.copySlice (ByteArray.mkEmpty identLen) 0 ⟨unsafeCast identPtr⟩ 0 identLen)

  let ctx ← handle.ref.get

  try
    let name := ident.toName
    match ctx.env.find? name with
    | some info =>
      let typeStr := toString (← Meta.ppExpr info.type)
      return unsafeCast typeStr
    | none =>
      return unsafeCast ""
  catch _ =>
    return unsafeCast ""

end LeanRepl.FFI
