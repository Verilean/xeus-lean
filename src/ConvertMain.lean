/-
ConvertMain — CLI driver for the Markdown → Jupyter / Lean
converter.

Usage:

  xlean-convert --to ipynb chapter.md           # → chapter.ipynb
  xlean-convert --to ipynb -o out.ipynb in.md   # explicit output
  xlean-convert --to lean  chapter.md           # → chapter.lean
  xlean-convert --to lean  -o out.lean in.md
  xlean-convert --to ipynb -                    # stdin → stdout

When `-o` is omitted, the output filename is derived from the
input by replacing the extension.  When the input is `-`, we
read from stdin.  When `-o` is `-` (or is omitted *and* input is
`-`), we write to stdout.
-/

import Convert
import Lean.Data.Json

open Convert
open Lean (Json)

inductive Target where
  | ipynb
  | lean
  deriving Repr, BEq

structure Opts where
  target  : Target := .ipynb
  input   : String := "-"
  output  : Option String := none

instance : Inhabited Opts := ⟨{}⟩

private def usage : String :=
  "usage: xlean-convert --to {ipynb|lean} [-o OUTPUT] INPUT.md\n\n" ++
  "  --to TARGET   ipynb (default) or lean (.lean:percent)\n" ++
  "  -o OUTPUT     output file; defaults to derived name; '-' = stdout\n" ++
  "  INPUT         input .md file; '-' = stdin\n"

private def parseArgs (argv : List String) : Except String Opts := do
  let mut opts : Opts := {}
  let mut posArgs : Array String := #[]
  let mut rest := argv
  while h : rest ≠ [] do
    match rest with
    | "--to" :: v :: tail =>
      match v with
      | "ipynb" => opts := { opts with target := .ipynb }
      | "lean"  => opts := { opts with target := .lean  }
      | other   => throw s!"unknown --to target: {other}"
      rest := tail
    | "-o" :: v :: tail =>
      opts := { opts with output := some v }
      rest := tail
    | "--help" :: _ | "-h" :: _ =>
      throw usage
    | a :: tail =>
      posArgs := posArgs.push a
      rest := tail
    | [] => rest := []
  if posArgs.size != 1 then
    throw s!"expected exactly one INPUT argument, got {posArgs.size}\n\n{usage}"
  pure { opts with input := posArgs[0]! }

private def deriveOutputName (input : String) (target : Target) : String :=
  let ext := match target with | .ipynb => ".ipynb" | .lean => ".lean"
  -- Strip a trailing .md / .markdown if present.
  let stem :=
    if input.endsWith ".md" then (input.dropEnd 3).toString
    else if input.endsWith ".markdown" then (input.dropEnd 9).toString
    else input
  stem ++ ext

private def readInput (path : String) : IO String := do
  if path == "-" then
    let stdin ← IO.getStdin
    stdin.readToEnd
  else
    IO.FS.readFile path

private def writeOutput (path : String) (content : String) : IO Unit :=
  if path == "-" then
    IO.print content
  else
    IO.FS.writeFile path content

unsafe def main (argv : List String) : IO UInt32 := do
  let opts ← match parseArgs argv with
    | .ok o => pure o
    | .error e => do
      IO.eprintln e
      return 2
  let src ← readInput opts.input
  let cells := Convert.parseMarkdown src
  let rendered :=
    match opts.target with
    | .ipynb =>
      -- Pretty-print with 1-space indent so .ipynb diffs are
      -- legible in code review.
      (Convert.cellsToIpynb cells).pretty 1
    | .lean =>
      Convert.cellsToPercent cells
  let outPath :=
    match opts.output with
    | some p => p
    | none =>
      if opts.input == "-" then "-"
      else deriveOutputName opts.input opts.target
  writeOutput outPath rendered
  return 0
