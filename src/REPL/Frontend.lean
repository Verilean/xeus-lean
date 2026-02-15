/-
Copyright (c) 2023 Scott Morrison. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Scott Morrison
-/
import Lean.Elab.Frontend

open Lean Elab

namespace Lean.Elab.IO

/--
Process commands using the synchronous FrontendM loop, accumulating
messages and info trees across commands.

In Lean 4.28+, `elabCommandTopLevel` resets `Command.State.messages` and
`infoState` at the start of each command. The old `Frontend.processCommands`
loop loses messages because the final `commandState` only contains messages
from the LAST command (usually the EOF/terminal command, which has none).

This version collects messages and trees after each command and accumulates
them, so output from `#check`, `#eval`, etc. is preserved.
-/
private partial def processCommandsAccum
    (accMsgs : MessageLog) (accTrees : PersistentArray InfoTree) :
    Frontend.FrontendM (MessageLog × PersistentArray InfoTree) := do
  let done ← Frontend.processCommand
  let cmdState ← Frontend.getCommandState
  let newMsgs := accMsgs ++ cmdState.messages
  let newTrees := accTrees ++ cmdState.infoState.trees
  if done then
    return (newMsgs, newTrees)
  else
    processCommandsAccum newMsgs newTrees

/--
Wrapper for command processing that enables info states, and returns
* the new command state
* messages (accumulated across all commands)
* info trees (accumulated across all commands)

Uses the synchronous FrontendM loop instead of the incremental snapshot
system (IO.processCommands) to avoid task/promise issues in WASM.
-/
def processCommandsWithInfoTrees
    (inputCtx : Parser.InputContext) (parserState : Parser.ModuleParserState)
    (commandState : Command.State) : IO (Command.State × List Message × List InfoTree) := do
  let commandState := { commandState with infoState.enabled := true }
  let ctx : Frontend.Context := { inputCtx }
  let initState : Frontend.State := {
    commandState := commandState
    parserState := parserState
    cmdPos := parserState.pos
    commands := #[]
  }
  let ((allMsgs, allTrees), finalState) ←
    (processCommandsAccum {} {} ctx).run initState
  pure (finalState.commandState, allMsgs.toList, allTrees.toList)

/--
Process some text input, with or without an existing command state.
If there is no existing environment, we parse the input for headers (e.g. import statements),
and create a new environment.
Otherwise, we add to the existing environment.

Returns:
1. The header-only command state (only useful when cmdState? is none)
2. The resulting command state after processing the entire input
3. List of messages
4. List of info trees
-/
def processInput (input : String) (cmdState? : Option Command.State)
    (opts : Options := {}) (fileName : Option String := none) :
    IO (Command.State × Command.State × List Message × List InfoTree) := unsafe do
  IO.eprintln "[processInput] ENTER"
  -- In WASM, .olean files are embedded at /lib/lean/ so sysroot is "/".
  -- Lean.findSysroot spawns `lean --print-prefix` which is impossible in WASM.
  let sysroot : System.FilePath := "/"
  IO.eprintln s!"[processInput] sysroot={sysroot}"
  Lean.initSearchPath sysroot
  IO.eprintln "[processInput] initSearchPath done"
  enableInitializersExecution
  let fileName   := fileName.getD "<input>"
  let inputCtx   := Parser.mkInputContext input fileName

  match cmdState? with
  | none => do
    IO.eprintln "[processInput] no cmdState, parsing header..."
    let (header, parserState, messages) ← Parser.parseHeader inputCtx
    IO.eprintln "[processInput] header parsed, calling processHeader..."
    -- Check if .olean files exist in the VFS
    let initOlean := System.FilePath.mk "/lib/lean/Init.olean"
    let initDir := System.FilePath.mk "/lib/lean/Init"
    let initOleanExists ← initOlean.pathExists
    let initDirExists ← initDir.isDir
    IO.eprintln s!"[processInput] /lib/lean/Init.olean exists={initOleanExists}, /lib/lean/Init isDir={initDirExists}"
    let sp ← Lean.searchPathRef.get
    IO.eprintln s!"[processInput] searchPath={sp}"
    let (env, messages) ← processHeader header opts messages inputCtx
    IO.eprintln s!"[processInput] processHeader done, env has {env.constants.fold (init := 0) fun n _ _ => n + 1} constants"
    -- Log header messages
    for m in messages.toList do
      let dataStr ← m.data.toString
      IO.eprintln s!"[processInput]   headerMsg: severity={m.severity}, data='{dataStr.take 200}'"
    let headerOnlyState := Command.mkState env messages opts
    IO.eprintln s!"[processInput] processing commands... (headerMsgs={messages.toList.length})"
    let (cmdState, messages, trees) ← processCommandsWithInfoTrees inputCtx parserState headerOnlyState
    IO.eprintln s!"[processInput] commands processed, {messages.length} messages"
    for m in messages do
      let dataStr ← m.data.toString
      IO.eprintln s!"[processInput]   msg: severity={m.severity}, data='{dataStr.take 100}'"
    return (headerOnlyState, cmdState, messages, trees)

  | some cmdStateBefore => do
    let envConsts := cmdStateBefore.env.constants.fold (init := 0) fun n _ _ => n + 1
    IO.eprintln s!"[processInput] existing cmdState, env has {envConsts} constants, {cmdStateBefore.messages.toList.length} existing msgs"
    IO.eprintln s!"[processInput] input='{input.take 80}'"
    let parserState : Parser.ModuleParserState := {}
    let (cmdStateAfter, messages, trees) ← processCommandsWithInfoTrees inputCtx parserState cmdStateBefore
    IO.eprintln s!"[processInput] commands processed, {messages.length} messages returned"
    for m in messages do
      let dataStr ← m.data.toString
      IO.eprintln s!"[processInput]   msg: severity={m.severity}, data='{dataStr.take 100}'"
    return (cmdStateBefore, cmdStateAfter, messages, trees)
