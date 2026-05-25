/-
ConvertMain — CLI driver for the Markdown → Jupyter / Lean / HTML
converter.

Usage:

  Single-file mode:
    xlean-convert --to ipynb chapter.md           # → chapter.ipynb
    xlean-convert --to ipynb -o out.ipynb in.md   # explicit output
    xlean-convert --to lean  chapter.md           # → chapter.lean
    xlean-convert --to html  chapter.md           # → chapter.html
    xlean-convert --to ipynb -                    # stdin → stdout

  Site mode (Markdown directory → static HTML site):
    xlean-convert --site docs/tutorial/md \
                  --output _site \
                  [--title "My Tutorial"]

  In site mode every `Ch*.md` (sorted) under the input directory
  becomes a chapter page; `README.md`, if present, supplies the
  index intro. Output directory is overwritten in-place.

When `-o` is omitted, the output filename is derived from the
input by replacing the extension. When the input is `-`, we
read from stdin. When `-o` is `-` (or is omitted *and* input is
`-`), we write to stdout.
-/

import Convert
import Lean.Data.Json

open Convert
open Lean (Json)

inductive Target where
  | ipynb
  | lean
  | html
  | md
  deriving Repr, BEq

structure Opts where
  /-- Site mode is requested via `--site DIR`.  When set, INPUT and
      --to are ignored and the directory is processed as a whole. -/
  site    : Option String := none
  /-- Site-mode title (defaults to "Tutorial"). -/
  title   : String := "Tutorial"
  /-- --eval mode: run the chapter through `lean --run` to bake
      `Display.*` / stdout outputs into the Markdown source. -/
  eval    : Bool := false
  target  : Target := .ipynb
  input   : String := "-"
  output  : Option String := none

instance : Inhabited Opts := ⟨{}⟩

private def usage : String :=
  "usage: xlean-convert --to {ipynb|lean|html|md} [-o OUTPUT] INPUT\n" ++
  "       xlean-convert --site DIR [-o OUTDIR] [--title TITLE]\n" ++
  "       xlean-convert --eval INPUT.md [-o OUTPUT.md]\n\n" ++
  "  --to TARGET   ipynb (default), lean (.lean:percent), html, or md\n" ++
  "  -o OUTPUT     output file (or directory for --site)\n" ++
  "                defaults to derived name; '-' = stdout\n" ++
  "  --site DIR    build a static HTML site from every Ch*.{md,ipynb}\n" ++
  "  --title TXT   site index title (site mode only)\n" ++
  "  --eval        run the chapter through `lean --run` to bake\n" ++
  "                Display.* and stdout outputs into the .md as\n" ++
  "                ```output:* fences (requires `lean` on PATH and\n" ++
  "                `Display` reachable via LEAN_PATH)\n" ++
  "  INPUT         input .md or .ipynb file; '-' = stdin (md)\n"

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
      | "html"  => opts := { opts with target := .html  }
      | "md"    => opts := { opts with target := .md    }
      | other   => throw s!"unknown --to target: {other}"
      rest := tail
    | "-o" :: v :: tail =>
      opts := { opts with output := some v }
      rest := tail
    | "--site" :: v :: tail =>
      opts := { opts with site := some v }
      rest := tail
    | "--title" :: v :: tail =>
      opts := { opts with title := v }
      rest := tail
    | "--eval" :: tail =>
      opts := { opts with eval := true }
      rest := tail
    | "--help" :: _ | "-h" :: _ =>
      throw usage
    | a :: tail =>
      posArgs := posArgs.push a
      rest := tail
    | [] => rest := []
  if opts.site.isSome then
    pure opts
  else
    if posArgs.size != 1 then
      throw s!"expected exactly one INPUT argument, got {posArgs.size}\n\n{usage}"
    pure { opts with input := posArgs[0]! }

private def deriveOutputName (input : String) (target : Target) : String :=
  let ext := match target with
    | .ipynb => ".ipynb"
    | .lean  => ".lean"
    | .html  => ".html"
    | .md    => ".md"
  -- Strip a trailing .md / .markdown / .ipynb if present.
  let stem :=
    if input.endsWith ".md" then (input.dropEnd 3).toString
    else if input.endsWith ".markdown" then (input.dropEnd 9).toString
    else if input.endsWith ".ipynb" then (input.dropEnd 6).toString
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

/-- Parse INPUT into cells, picking the parser by file extension.
    `.ipynb` → Jupyter parser (keeps outputs); anything else → md. -/
private def loadCells (path : String) : IO (Array Convert.Cell) := do
  let src ← readInput path
  if path.endsWith ".ipynb" then
    match Convert.parseIpynb src with
    | .ok cs => pure cs
    | .error e => do
      IO.eprintln s!"ipynb parse error: {e}"
      pure #[]
  else
    pure (Convert.parseMarkdown src)

/-- Single-file conversion path (non-site mode). -/
private def runSingle (opts : Opts) : IO UInt32 := do
  let cells ← loadCells opts.input
  let rendered :=
    match opts.target with
    | .ipynb => (Convert.cellsToIpynb cells).pretty 1
    | .lean  => Convert.cellsToPercent cells
    | .html  => Convert.cellsToHtml cells
    | .md    => Convert.cellsToMarkdown cells
  let outPath :=
    match opts.output with
    | some p => p
    | none =>
      if opts.input == "-" then "-"
      else deriveOutputName opts.input opts.target
  writeOutput outPath rendered
  return 0

/-- Replace a trailing `.md` / `.markdown` / `.ipynb` with `.html`. -/
private def mdToHtml (name : String) : String :=
  if name.endsWith ".md" then (name.dropEnd 3).toString ++ ".html"
  else if name.endsWith ".markdown" then (name.dropEnd 9).toString ++ ".html"
  else if name.endsWith ".ipynb" then (name.dropEnd 6).toString ++ ".html"
  else name ++ ".html"

/-- Site-mode conversion: walk INPUT_DIR, render Ch*.md to
    HTML chapter pages and emit an index.html + style.css. -/
private def runSite (opts : Opts) : IO UInt32 := do
  let inputDir := opts.site.get!
  let outputDir := opts.output.getD "_site"
  let inputPath  := System.FilePath.mk inputDir
  let outputPath := System.FilePath.mk outputDir
  if ! (← inputPath.isDir) then
    IO.eprintln s!"--site: not a directory: {inputDir}"
    return 2
  IO.FS.createDirAll outputPath

  -- Discover Ch*.{md,ipynb} inputs, sorted lexicographically.
  -- If both Ch01.md and Ch01.ipynb exist, the ipynb wins (it has
  -- outputs baked in).
  let entries ← inputPath.readDir
  let chFiles : Array String :=
    entries.filterMap fun e =>
      let n := e.fileName
      if n.startsWith "Ch" &&
         (n.endsWith ".md" || n.endsWith ".markdown" || n.endsWith ".ipynb")
      then some n else none
  -- De-dup by stem, preferring ipynb.
  let stemOf (s : String) : String :=
    if s.endsWith ".ipynb" then (s.dropEnd 6).toString
    else if s.endsWith ".md" then (s.dropEnd 3).toString
    else if s.endsWith ".markdown" then (s.dropEnd 9).toString
    else s
  let chFiles : Array String := Id.run do
    let mut seen : Std.HashMap String String := {}
    for f in chFiles do
      let stem := stemOf f
      match seen[stem]? with
      | none => seen := seen.insert stem f
      | some prev =>
        -- Prefer ipynb when both exist.
        if f.endsWith ".ipynb" then seen := seen.insert stem f
        else if prev.endsWith ".ipynb" then pure ()
        else seen := seen.insert stem f
    pure (seen.toArray.map (·.2))
  let chFiles := chFiles.qsort (· < ·)
  if chFiles.isEmpty then
    IO.eprintln s!"--site: no Ch*.md / Ch*.ipynb files in {inputDir}"
    return 2

  -- First pass: parse every chapter, extract title.
  let mut chapters : Array (String × String × Array Convert.Cell) := #[]
  for fname in chFiles do
    let cells ← loadCells (inputPath / fname).toString
    let title := Convert.chapterTitle cells
    chapters := chapters.push (mdToHtml fname, title, cells)

  let toc : Array (String × String) :=
    chapters.map fun (f, t, _) => (f, t)

  -- Second pass: write each chapter with prev/next nav + sidebar.
  let n := chapters.size
  for i in [:n] do
    let (fname, title, cells) := chapters[i]!
    let prev? := if i > 0 then
                   let (pf, pt, _) := chapters[i-1]!
                   some (pf, pt)
                 else none
    let next? := if i + 1 < n then
                   let (nf, nt, _) := chapters[i+1]!
                   some (nf, nt)
                 else none
    let sidebar := Convert.renderSidebar opts.title toc (some fname)
    let html := Convert.cellsToHtml cells
                  (title := some title)
                  (prev? := prev?) (next? := next?)
                  (relRoot := "./")
                  (sidebar := sidebar)
    IO.FS.writeFile (outputPath / fname) html
    IO.println s!"wrote {outputDir}/{fname}  ({title})"

  -- Index page (with same sidebar).
  let index := Convert.renderSiteIndex opts.title toc
  IO.FS.writeFile (outputPath / "index.html") index
  IO.println s!"wrote {outputDir}/index.html  ({opts.title})"

  -- Stylesheet.
  IO.FS.writeFile (outputPath / "style.css") Convert.defaultStylesheet
  IO.println s!"wrote {outputDir}/style.css"

  return 0

/-- --eval mode: render the cells as a .lean batch, run it via
    `lean --run`, parse the stdout back into per-cell outputs, and
    serialise the augmented cell list as Markdown.

    The temp .lean file is dumped under `/tmp/xlean-eval-<pid>/`.
    We pass `LEAN_PATH` from the environment through to the child
    so it can find Display etc. -/
private def runEval (opts : Opts) : IO UInt32 := do
  let cells ← loadCells opts.input
  let leanSrc := Convert.renderForEval cells
  -- Write to a temp file (lean --run needs a path, not stdin).
  let tmpDir : System.FilePath :=
    System.FilePath.mk "/tmp" / s!"xlean-eval-{← IO.rand 100000 999999}"
  IO.FS.createDirAll tmpDir
  let tmpFile := tmpDir / "Eval.lean"
  IO.FS.writeFile tmpFile leanSrc

  -- `lean FILE` evaluates the file top-to-bottom (executing #eval
  -- as it goes) and exits cleanly without needing a `main`.
  IO.eprintln s!"running: lean {tmpFile}"
  let proc ← IO.Process.spawn {
    cmd := "lean",
    args := #[tmpFile.toString],
    stdout := .piped,
    stderr := .piped,
  }
  let stdout ← proc.stdout.readToEnd
  let stderr ← proc.stderr.readToEnd
  let ec ← proc.wait
  if ec != 0 then
    IO.eprintln s!"lean --run failed (exit {ec})"
    IO.eprintln stderr
    -- Still try to attach whatever outputs we got, so the user
    -- can see partial progress, but exit non-zero.
    pure ()

  let chunks := Convert.splitByCellEnd stdout
  let newCells := Convert.attachEvalOutputs cells chunks
  let md := Convert.cellsToMarkdown newCells
  let outPath :=
    match opts.output with
    | some p => p
    | none =>
      if opts.input == "-" then "-"
      else deriveOutputName opts.input .md
  writeOutput outPath md
  return (if ec != 0 then 1 else 0)

unsafe def main (argv : List String) : IO UInt32 := do
  let opts ← match parseArgs argv with
    | .ok o => pure o
    | .error e => do
      IO.eprintln e
      return 2
  if opts.site.isSome then runSite opts
  else if opts.eval then runEval opts
  else runSingle opts
