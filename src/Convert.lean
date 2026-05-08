/-
# Convert.lean — Markdown → Jupyter notebook / lean:percent

A small pure-Lean library that splits a Markdown document into a
sequence of cells (Markdown vs. code), then renders the result
either as a Jupyter `.ipynb` (JSON) or as a jupytext-style
`.lean:percent` source file.

## Why

xeus-lean already runs Lean inside Jupyter via the `xeus-lean`
kernel. Authors often want to write tutorial chapters in plain
Markdown (reviewable, Git-diff-friendly, render directly on
GitHub) and then *generate* the executable `.ipynb` and a Lean
source for `lake build` to type-check.

This module is the conversion side of that pipeline:

```
chapter.md  ──┬──→  chapter.ipynb   (xlean convert --to ipynb)
              └──→  chapter.lean    (xlean convert --to lean)
```

The forward path (Markdown → .ipynb) feeds JupyterLab. The side
path (Markdown → .lean) lets users wire `lake build` into CI so
every code cell type-checks even when no kernel is running.

## Cell-detection rules

We treat the document as a stream of lines and look for
**fenced code blocks** (` ``` `).  A fence opens with
` ```LANG ` (any non-whitespace tag) and closes with a bare
` ``` ` on its own line.

- A fence whose tag is `lean` (case-insensitive) → **code cell**,
  body becomes a Jupyter `code` cell with the `xeus-lean` kernel.
- Any other fence (`bash`, `verilog`, etc.) **stays in the
  surrounding Markdown cell** — those are example snippets the
  author shows but doesn't want to execute.
- Any text outside a fence accumulates into a **Markdown cell**.
- Consecutive Markdown cells are merged.

## Round-trip / `--to lean` format

The `.lean` output is a `lean:percent` document compatible with
jupytext's `hs:percent` parser (Lean and Haskell both use `--`
for line comments, so this works without registering a custom
language with jupytext upstream):

```
-- %% [markdown]
-- # Heading
--
-- prose ...

-- %%
def x := 1
```

Markdown cells become `-- %% [markdown]` blocks where every line
of body text is prefixed with `-- `.  Code cells become bare
`-- %%` blocks with the body verbatim.
-/

import Lean.Data.Json

namespace Convert

/-! ## 1. Cell representation -/

/-- One cell of the parsed document. -/
inductive Cell where
  | markdown (lines : Array String)
  | code     (lines : Array String)
  deriving Repr, Inhabited

namespace Cell

def isMarkdown : Cell → Bool
  | .markdown _ => true
  | .code     _ => false

def isCode : Cell → Bool
  | .code _ => true
  | _       => false

/-- Source of a cell as a single string (Jupyter expects an array
    of lines, each ending in `\n`, or a single string).  We keep
    them as arrays-of-lines and join when serialising. -/
def lines : Cell → Array String
  | .markdown ls | .code ls => ls

end Cell

/-! ## 2. Markdown → cells (the parser) -/

/-- Result of consuming one input line. -/
private inductive LineEvent where
  | openFence  (tag : String)  -- e.g. "lean"
  | closeFence
  | plain (line : String)
  deriving Repr

/-- Decide whether `line` is a fence opener / closer / plain.
    A fence is a line whose first non-space characters are `` ``` ``.
    Anything after the backticks is the language tag. -/
private def classify (line : String) : LineEvent :=
  let trimmed := line.trimAsciiStart.toString
  if trimmed.startsWith "```" then
    let after := ((trimmed.drop 3).trimAscii).toString
    if after.isEmpty then .closeFence else .openFence after
  else
    .plain line

/-- Strip a trailing CR from a line (for Windows line endings). -/
private def stripCR (line : String) : String :=
  if line.endsWith "\r" then line.dropEnd 1 |>.toString else line

/-- Trim trailing empty lines from a buffer (useful when a
    Markdown cell ends just before a fence and the splitter left a
    blank line behind). -/
private def trimTrailingEmpty (buf : Array String) : Array String := Id.run do
  let mut b := buf
  while b.size > 0 && b.back!.isEmpty do
    b := b.pop
  pure b

/-- Parse Markdown source into a sequence of cells. -/
def parseMarkdown (src : String) : Array Cell := Id.run do
  let lines := src.splitOn "\n" |>.map stripCR |>.toArray
  let mut cells   : Array Cell := #[]
  let mut mdBuf   : Array String := #[]
  let mut codeBuf : Array String := #[]
  let mut inLeanFence := false
  let mut inOtherFence := false
  let flushMd : Array String → Array Cell → Array Cell := fun buf c =>
    let trimmed := trimTrailingEmpty buf
    if trimmed.isEmpty || trimmed.all String.isEmpty then c
    else c.push (.markdown trimmed)
  let flushCode : Array String → Array Cell → Array Cell := fun buf c =>
    if buf.isEmpty then c else c.push (.code buf)
  for raw in lines do
    if inLeanFence then
      match classify raw with
      | .closeFence | .openFence _ =>
        cells   := flushCode codeBuf cells
        codeBuf := #[]
        inLeanFence := false
      | .plain line =>
        codeBuf := codeBuf.push line
    else if inOtherFence then
      mdBuf := mdBuf.push raw
      match classify raw with
      | .closeFence => inOtherFence := false
      | _           => pure ()
    else
      match classify raw with
      | .openFence tag =>
        if tag.toLower == "lean" then
          cells := flushMd mdBuf cells
          mdBuf := #[]
          inLeanFence := true
        else
          mdBuf := mdBuf.push raw
          inOtherFence := true
      | _ =>
        mdBuf := mdBuf.push raw
  cells := flushMd mdBuf cells
  cells := flushCode codeBuf cells
  pure cells

/-! ## 3. Cells → Jupyter `.ipynb` JSON -/

open Lean (Json ToJson)

/-- Turn an array of source lines into the Jupyter `source`
    representation.  Jupyter expects an array of strings, each
    line ending in `\n` (except the last). -/
private def linesToSource (ls : Array String) : Array String := Id.run do
  if ls.isEmpty then return #[]
  -- Drop trailing empty lines (a fence body usually has none, but
  -- a Markdown cell might).
  let mut trimmed := ls
  while trimmed.size > 0 && trimmed.back!.isEmpty do
    trimmed := trimmed.pop
  let n := trimmed.size
  let mut out : Array String := Array.mkEmpty n
  for i in [:n] do
    let line := trimmed[i]!
    if i + 1 == n then
      out := out.push line
    else
      out := out.push (line ++ "\n")
  pure out

private def cellToJson : Cell → Json
  | .markdown ls =>
    Json.mkObj [
      ("cell_type", "markdown"),
      ("metadata",  Json.mkObj []),
      ("source",    Json.arr ((linesToSource ls).map Json.str))
    ]
  | .code ls =>
    Json.mkObj [
      ("cell_type",       "code"),
      ("execution_count", Json.null),
      ("metadata",        Json.mkObj []),
      ("outputs",         Json.arr #[]),
      ("source",          Json.arr ((linesToSource ls).map Json.str))
    ]

/-- Top-level Jupyter notebook metadata.  We pin the kernelspec to
    `xeus-lean` (the kernel name xeus-lean's `installKernel` script
    registers) and language to `lean4`. -/
private def notebookMetadata : Json :=
  Json.mkObj [
    ("kernelspec", Json.mkObj [
      ("display_name", "Lean 4"),
      ("language",     "lean4"),
      ("name",         "xeus-lean")
    ]),
    ("language_info", Json.mkObj [
      ("file_extension", ".lean"),
      ("name",           "lean4")
    ])
  ]

/-- Serialise cells as a Jupyter `.ipynb` JSON value. -/
def cellsToIpynb (cells : Array Cell) : Json :=
  Json.mkObj [
    ("cells",          Json.arr (cells.map cellToJson)),
    ("metadata",       notebookMetadata),
    ("nbformat",       Json.num 4),
    ("nbformat_minor", Json.num 5)
  ]

/-! ## 4. Cells → `lean:percent` source -/

/-- Render a single cell in jupytext percent format. -/
private def cellToPercent : Cell → String
  | .markdown ls =>
    let body := ls.foldl (fun acc l =>
      if l.isEmpty then acc ++ "--\n" else acc ++ "-- " ++ l ++ "\n") ""
    "-- %% [markdown]\n" ++ body
  | .code ls =>
    let body := ls.foldl (fun acc l => acc ++ l ++ "\n") ""
    "-- %%\n" ++ body

/-- Header cell that points jupytext at the right kernel.  Required
    so `jupytext --to ipynb` produces a notebook with `xeus-lean`
    as the kernel; without it, jupytext falls back to no kernel. -/
private def percentHeader : String :=
  "-- ---\n" ++
  "-- jupyter:\n" ++
  "--   kernelspec:\n" ++
  "--     display_name: Lean 4\n" ++
  "--     language: lean4\n" ++
  "--     name: xeus-lean\n" ++
  "-- ---\n"

/-- Serialise cells as `lean:percent` text with a kernel header. -/
def cellsToPercent (cells : Array Cell) : String :=
  let parts := cells.map cellToPercent
  let body := parts.foldl (fun acc s => acc ++ "\n" ++ s) ""
  percentHeader ++ body

end Convert
