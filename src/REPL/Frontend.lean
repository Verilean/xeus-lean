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
  -- Auto-import Display + any extras the deployment declared on the
  -- first cell.  Why: the Lean REPL only allows `import` at the very
  -- start of a "file", and each cell after the first reuses the prior
  -- cmdState — so once any cell has run, the user can no longer
  -- import anything.  We pre-inject the imports the kernel ships
  -- with so `#help_x`, `Display.html`, etc. work without the user
  -- having to remember to put `import Display` in cell 1.
  --
  -- The auto-import only runs when `cmdState?` is `none` (i.e. the
  -- very first cell).  User code in that cell still runs after the
  -- imports.
  --
  -- Extension: a downstream lib (anything shipped via EXTRA_WASM_DIRS)
  -- registers its own auto-imports by writing one module name per
  -- line into a file under one of these names somewhere on the
  -- search path:
  --
  --     /lib/lean/.xeus-auto-imports          (WASM VFS)
  --     <root>/.xeus-auto-imports             (each native search root)
  --
  -- Lines starting with `#` and blank lines are ignored.  Each
  -- listed module is imported only if its olean is actually
  -- present (so an outdated registry doesn't fail elaboration).
  -- xeus-lean itself names no third-party module — they appear
  -- only inside the .xeus-auto-imports file the third-party build
  -- script writes.
  let input ←
    if cmdState?.isNone then do
      -- 1. Compute the list of search roots to probe.  WASM uses the
      --    fixed /lib/lean prefix because LEAN_PATH isn't populated
      --    from the kernelspec there; native uses the search path.
      let roots ← if isWasm then
        pure [System.FilePath.mk "/lib/lean"]
      else
        Lean.searchPathRef.get
      let oleanExists (mod : String) : IO Bool := do
        let rel : System.FilePath := System.FilePath.mk (mod.replace "." "/" ++ ".olean")
        for root in roots do
          if (← (root / rel).pathExists) then return true
        return false
      -- 2. Always-on auto-import is just Display.  Anything else is
      --    sourced from .xeus-auto-imports registries.
      let coreImports := if (← oleanExists "Display") then "import Display\n" else ""
      -- 3. Read each .xeus-auto-imports file under the search roots
      --    and collect distinct module names.
      let mut extras : List String := []
      let mut seen : Std.HashSet String := {}
      for root in roots do
        let registry := root / ".xeus-auto-imports"
        if ← registry.pathExists then
          let body ← IO.FS.readFile registry
          for line in body.splitOn "\n" do
            let line := line.trim
            if line.isEmpty || line.startsWith "#" then continue
            if seen.contains line then continue
            seen := seen.insert line
            extras := extras ++ [line]
      -- 4. Drop registry entries whose olean is missing — keeps a
      --    stale list from breaking the first cell.
      let mut extraImports := ""
      for mod in extras do
        if ← oleanExists mod then
          extraImports := extraImports ++ s!"import {mod}\n"
        else
          IO.eprintln s!"[processInput] .xeus-auto-imports: skipping `{mod}` (olean not found)"
      pure (coreImports ++ extraImports ++ input)
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
    -- Check core modules (Std/Lean/Display).  Anything else lives
    -- under a third-party search root and isn't worth a diagnostic
    -- here — the auto-import block above already logged misses.
    let stdOlean ← (System.FilePath.mk "/lib/lean/Std.olean").pathExists
    let leanOlean ← (System.FilePath.mk "/lib/lean/Lean.olean").pathExists
    let displayOlean ← (System.FilePath.mk "/lib/lean/Display.olean").pathExists
    IO.eprintln s!"[processInput] Std.olean={stdOlean} Lean.olean={leanOlean} Display.olean={displayOlean}"
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
