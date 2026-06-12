/-
  MCP/LeanSession — a thin wrapper around the Lean REPL that the MCP
  tools call into.

  v0 stub: routes everything through Lean's process-spawn (lean
  --run) on each call.  This is correct but slow (no persistent env
  between calls).  v1 will share a single REPL instance — the same
  one xeus uses — so the env carries across tool invocations the
  way notebook cells do.

  The structure here is the eventual public shape; for now the
  `eval` implementation is the placeholder.
-/

import Lean.Data.Json

namespace XLean.MCP

open Lean (Json)

/-- A persistent Lean session.  v0 fields are minimal; v1 will hold a
    pointer to the running REPL's environment id (the same `envId`
    `WasmRepl.lean` threads through xeus). -/
structure LeanSession where
  /-- Next env-id to use; advances after every successful eval.  v0
      stub. -/
  envCounter : Nat := 0

namespace LeanSession

/-- Create a fresh session.  Named `fresh` rather than `mk` so it
    doesn't collide with the structure's auto-generated constructor. -/
def fresh : LeanSession := {}

/-- Evaluate a Lean code snippet and return the textual messages.

    v0: shells out to `lean` on each call by writing the code to a
    temp file.  No env persistence — every call sees a clean slate.
    Good enough to sanity-check tool wiring; not good enough to use
    in earnest.

    v1 will share state with the REPL the kernel uses. -/
def eval (_s : LeanSession) (code : String) : IO String := do
  -- Write the code to a temp file and invoke `lean` on it.  The
  -- piped-stdin route used to be the obvious choice but Lean 4.28's
  -- Process API made closing stdin while still reading stdout
  -- noticeably awkward.  A temp file is the simpler v0.
  let (_handle, path) ← IO.FS.createTempFile
  IO.FS.writeFile path code
  -- If the MCP host's workspace looks like a Lake project, run the
  -- snippet through `lake env lean` so transitive deps (Sparkle,
  -- Mathlib, etc.) resolve.  Otherwise fall back to a bare `lean`,
  -- which is enough for stdlib-only snippets.  Without this branch,
  -- `import Sparkle` from a `lean_eval` call inside a Sparkle
  -- checkout fails with "unknown module prefix 'Sparkle'" because the
  -- bare `lean` only sees the toolchain's stdlib search path.
  let inLakeProject ← System.FilePath.pathExists "lakefile.lean"
  let inLakeTomlProject ← System.FilePath.pathExists "lakefile.toml"
  let (cmd, args) :=
    if inLakeProject || inLakeTomlProject then
      ("lake", #["env", "lean", path.toString])
    else
      ("lean", #[path.toString])
  let out ← IO.Process.output { cmd, args }
  -- The `IO.FS.removeFile` is best-effort; if the file was already
  -- swept away we don't care.
  try IO.FS.removeFile path catch _ => pure ()
  if out.stderr.isEmpty then
    pure out.stdout
  else if out.stdout.isEmpty then
    pure out.stderr
  else
    pure (out.stdout ++ "\n" ++ out.stderr)

/-- Bump the internal counter after a successful eval.  Pure
    placeholder until the real env tracking lands. -/
def advance (s : LeanSession) : LeanSession :=
  { s with envCounter := s.envCounter + 1 }

end LeanSession

end XLean.MCP
