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
private partial def processCommandsAccumAt
    (n : Nat) (accMsgs : MessageLog) (accTrees : PersistentArray InfoTree) :
    Frontend.FrontendM (MessageLog × PersistentArray InfoTree) := do
  IO.eprintln s!"[processCommandsAccum] #{n} ENTER"
  let done ← Frontend.processCommand
  IO.eprintln s!"[processCommandsAccum] #{n} processCommand DONE, done={done}"
  let cmdState ← Frontend.getCommandState
  let newMsgs := accMsgs ++ cmdState.messages
  let newTrees := accTrees ++ cmdState.infoState.trees
  if done then
    return (newMsgs, newTrees)
  else
    processCommandsAccumAt (n + 1) newMsgs newTrees

private def processCommandsAccum
    (accMsgs : MessageLog) (accTrees : PersistentArray InfoTree) :
    Frontend.FrontendM (MessageLog × PersistentArray InfoTree) :=
  processCommandsAccumAt 0 accMsgs accTrees

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
  -- In WASM the .olean files are embedded at /lib/lean/ so sysroot is "/".
  -- Lean.findSysroot would spawn `lean --print-prefix`, which is impossible
  -- in WASM but is the right thing on a native build. Detect by probing
  -- for the embedded VFS file; fall back to findSysroot otherwise.
  let wasmInit := System.FilePath.mk "/lib/lean/Init.olean"
  let isWasm   ← wasmInit.pathExists
  let sysroot ← if isWasm then pure (System.FilePath.mk "/") else Lean.findSysroot
  IO.eprintln s!"[processInput] sysroot={sysroot} (wasm={isWasm})"
  Lean.initSearchPath sysroot
  IO.eprintln "[processInput] initSearchPath done"
  enableInitializersExecution
  let fileName   := fileName.getD "<input>"
  -- Auto-import Display (and, when present, Sparkle / Hesper) on the
  -- first cell. Why: the Lean REPL only allows `import` at the very
  -- start of a "file", and each cell after the first reuses the prior
  -- cmdState — so once any cell has run, the user can no longer
  -- import anything. We pre-inject the imports that ship with the
  -- kernel so `#help_x`, `Display.html`, etc. work without the user
  -- having to remember to put `import Display` in cell 1.
  --
  -- The auto-import only runs when `cmdState?` is `none` (i.e. the
  -- very first cell). User code in that cell still runs after the
  -- imports — anything the user typed is concatenated.
  --
  -- WASM gates each pre-import on the olean being in the embedded
  -- VFS (because trimmed-down WASM kernels may drop Sparkle/Hesper).
  -- Native always ships Display via lean-toolchain, but Sparkle and
  -- Hesper may be absent in the base image; gate those by checking
  -- their olean path in the build's lean search path.
  let input ←
    if cmdState?.isNone then do
      let imports ← if isWasm then do
        let hasSparkle ← (System.FilePath.mk "/lib/lean/Sparkle.olean").pathExists
        let hasHesper  ← (System.FilePath.mk "/lib/lean/Hesper/WGSL/DSL.olean").pathExists
        pure <|
          "import Display\n"
          ++ (if hasSparkle then "import Sparkle\n" else "")
          ++ (if hasHesper  then "import Hesper.WGSL.DSL\n" else "")
      else do
        -- Probe for each module via LEAN_PATH (set by the kernelspec).
        -- A module foo.bar.Baz lives at <root>/foo/bar/Baz.olean for
        -- some root in LEAN_PATH; if none of those roots has the
        -- file, the module isn't available and we skip its import.
        let leanPath ← Lean.searchPathRef.get
        let probe (rel : System.FilePath) : IO Bool := do
          for root in leanPath do
            if (← (root / rel).pathExists) then return true
          return false
        let hasDisplay ← probe ("Display.olean" : System.FilePath)
        let hasSparkle ← probe ("Sparkle.olean" : System.FilePath)
        let hasHesper  ← probe (("Hesper" : System.FilePath) / "WGSL" / "DSL.olean")
        pure <|
          (if hasDisplay then "import Display\n" else "")
          ++ (if hasSparkle then "import Sparkle\n" else "")
          ++ (if hasHesper  then "import Hesper.WGSL.DSL\n" else "")
      pure (imports ++ input)
    else
      pure input
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
    -- Check additional modules
    let stdOlean ← (System.FilePath.mk "/lib/lean/Std.olean").pathExists
    let leanOlean ← (System.FilePath.mk "/lib/lean/Lean.olean").pathExists
    let sparkleOlean ← (System.FilePath.mk "/lib/lean/Sparkle.olean").pathExists
    let displayOlean ← (System.FilePath.mk "/lib/lean/Display.olean").pathExists
    IO.eprintln s!"[processInput] Std.olean={stdOlean} Lean.olean={leanOlean} Sparkle.olean={sparkleOlean} Display.olean={displayOlean}"
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
