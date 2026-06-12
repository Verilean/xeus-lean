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

/-- A single output attached to a code cell.

    `mime` is the empty string for plain stream output (stdout);
    otherwise a Jupyter MIME type like "text/html", "text/latex",
    "image/svg+xml", "text/markdown", or "text/plain" with an
    associated `language` hint (e.g. "verilog") so syntax
    highlighting can still kick in for plain-text outputs of a
    known language. -/
structure CellOutput where
  /-- MIME type (e.g. "text/html"); "" for plain stream output. -/
  mime     : String := ""
  /-- Highlight.js language tag (used for plain-text outputs of a
      known language: "verilog", "json", etc.).  Ignored when
      `mime` is non-empty and non-"text/plain". -/
  language : String := ""
  /-- Raw output body, line-split (no trailing newlines). -/
  lines    : Array String
  deriving Repr, Inhabited

/-- One cell of the parsed document.

    Code cells carry their evaluated outputs alongside the source.
    This is the same model Jupyter uses internally, and it lets a
    single `.md` (with ` ```output:* ` fences) round-trip cleanly
    to `.ipynb` and back.  Markdown cells carry no outputs. -/
inductive Cell where
  | markdown (lines : Array String)
  | code     (lines : Array String) (outputs : Array CellOutput := #[])
  deriving Repr, Inhabited

namespace Cell

def isMarkdown : Cell → Bool
  | .markdown _ => true
  | .code _ _   => false

def isCode : Cell → Bool
  | .code _ _ => true
  | _         => false

/-- Source of a cell as a single string (Jupyter expects an array
    of lines, each ending in `\n`, or a single string).  We keep
    them as arrays-of-lines and join when serialising. -/
def lines : Cell → Array String
  | .markdown ls | .code ls _ => ls

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

/-- Decode an `output[:MIME]` fence tag.

    Returns `(mime, language)` where both fields follow the
    `CellOutput` convention:
      * `output`                → ("", "")            stream / stdout
      * `output:html`           → ("text/html", "")
      * `output:svg`            → ("image/svg+xml", "")
      * `output:latex`          → ("text/latex", "")
      * `output:markdown` / `:md` → ("text/markdown", "")
      * `output:json`           → ("application/json", "")
      * `output:LANG` (verilog, c++, ...) → ("text/plain", LANG)
    Returns `none` if the tag is not an `output[:...]` form. -/
private def parseOutputTag (tag : String) : Option (String × String) :=
  let lower := tag.toLower
  if lower == "output" then some ("", "")
  else if lower.startsWith "output:" then
    let sub := (lower.drop 7).toString
    match sub with
    | "html"     => some ("text/html", "")
    | "svg"      => some ("image/svg+xml", "")
    | "latex"    => some ("text/latex", "")
    | "markdown" => some ("text/markdown", "")
    | "md"       => some ("text/markdown", "")
    | "json"     => some ("application/json", "")
    | "plain"    => some ("text/plain", "")
    | "text"     => some ("", "")
    | lang       => some ("text/plain", lang)
  else none

/-- Parse Markdown source into a sequence of cells. -/
def parseMarkdown (src : String) : Array Cell := Id.run do
  let lines := src.splitOn "\n" |>.map stripCR |>.toArray
  let mut cells    : Array Cell := #[]
  let mut mdBuf    : Array String := #[]
  let mut codeBuf  : Array String := #[]
  let mut outBuf   : Array String := #[]
  let mut outs     : Array CellOutput := #[]
  let mut curOutMime : String := ""
  let mut curOutLang : String := ""
  let mut inLeanFence := false
  let mut inOutputFence := false
  let mut inOtherFence := false
  let mut pendingCode := false   -- a Lean code cell is open and we
                                 -- might still attach more outputs
  let flushMd : Array String → Array Cell → Array Cell := fun buf c =>
    let trimmed := trimTrailingEmpty buf
    if trimmed.isEmpty || trimmed.all String.isEmpty then c
    else c.push (.markdown trimmed)
  for raw in lines do
    if inLeanFence then
      match classify raw with
      | .closeFence | .openFence _ =>
        inLeanFence := false
        pendingCode := true  -- defer pushing until we know if there are outputs
      | .plain line =>
        codeBuf := codeBuf.push line
    else if inOutputFence then
      match classify raw with
      | .closeFence | .openFence _ =>
        outs := outs.push { mime := curOutMime, language := curOutLang, lines := outBuf }
        outBuf := #[]
        inOutputFence := false
      | .plain line =>
        outBuf := outBuf.push line
    else if inOtherFence then
      mdBuf := mdBuf.push raw
      match classify raw with
      | .closeFence => inOtherFence := false
      | _           => pure ()
    else
      match classify raw with
      | .openFence tag =>
        let tagLower := tag.toLower
        if tagLower == "lean" then
          -- Starting a new lean cell: finalise any pending one.
          if pendingCode then
            cells := flushMd mdBuf cells; mdBuf := #[]
            cells := cells.push (.code codeBuf outs)
            codeBuf := #[]; outs := #[]; pendingCode := false
          else
            cells := flushMd mdBuf cells; mdBuf := #[]
          inLeanFence := true
        else
          match parseOutputTag tag with
          | some (mime, lang) =>
            if pendingCode then
              -- Attach this output to the still-open code cell.
              curOutMime := mime; curOutLang := lang; inOutputFence := true
            else
              -- Stray output fence with no preceding lean cell:
              -- treat as illustrative inside the surrounding
              -- markdown (same fallback as ```bash etc.).
              mdBuf := mdBuf.push raw
              inOtherFence := true
          | none =>
            -- If we had a pending code cell waiting for outputs,
            -- this non-output fence closes it.
            if pendingCode then
              cells := flushMd mdBuf cells; mdBuf := #[]
              cells := cells.push (.code codeBuf outs)
              codeBuf := #[]; outs := #[]; pendingCode := false
            mdBuf := mdBuf.push raw
            inOtherFence := true
      | _ =>
        -- Non-fence line.  A blank line after a code cell is
        -- allowed before its outputs; otherwise close the code.
        if pendingCode && !raw.trimAscii.toString.isEmpty then
          cells := flushMd mdBuf cells; mdBuf := #[]
          cells := cells.push (.code codeBuf outs)
          codeBuf := #[]; outs := #[]; pendingCode := false
        mdBuf := mdBuf.push raw
  -- Flush at EOF.
  if pendingCode then
    cells := flushMd mdBuf cells; mdBuf := #[]
    cells := cells.push (.code codeBuf outs)
    codeBuf := #[]; outs := #[]
  cells := flushMd mdBuf cells
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

/-- Serialise one CellOutput as a Jupyter cell output value.

    Empty mime → `stream` output.
    `text/plain` with a language hint → still `display_data` with
    a `text/plain` payload (the language hint travels in
    `metadata.xleanLanguage` so reverse conversion can recover the
    fence tag). -/
private def outputToJson (o : CellOutput) : Json :=
  let body := linesToSource o.lines
  if o.mime.isEmpty then
    Json.mkObj [
      ("output_type", "stream"),
      ("name",        "stdout"),
      ("text",        Json.arr (body.map Json.str))
    ]
  else
    let dataLines := Json.arr (body.map Json.str)
    let metaJson :=
      if o.language.isEmpty then Json.mkObj []
      else Json.mkObj [("xleanLanguage", Json.str o.language)]
    Json.mkObj [
      ("output_type", "display_data"),
      ("data",        Json.mkObj [(o.mime, dataLines)]),
      ("metadata",    metaJson)
    ]

private def cellToJson : Cell → Json
  | .markdown ls =>
    Json.mkObj [
      ("cell_type", "markdown"),
      ("metadata",  Json.mkObj []),
      ("source",    Json.arr ((linesToSource ls).map Json.str))
    ]
  | .code ls outs =>
    Json.mkObj [
      ("cell_type",       "code"),
      ("execution_count", Json.null),
      ("metadata",        Json.mkObj []),
      ("outputs",         Json.arr (outs.map outputToJson)),
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

/-- Render a single cell in jupytext percent format.

    Outputs are *dropped* in the .lean:percent output — that
    format is for `lake build` typechecking, not display.  Use
    `--to md` if you want a round-trippable source-with-outputs. -/
private def cellToPercent : Cell → String
  | .markdown ls =>
    let body := ls.foldl (fun acc l =>
      if l.isEmpty then acc ++ "--\n" else acc ++ "-- " ++ l ++ "\n") ""
    "-- %% [markdown]\n" ++ body
  | .code ls _ =>
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

/-! ## 5. Cells → static HTML (no kernel)

This branch is for *published* documentation — a single self-
contained HTML file per chapter, no JS evaluation, no kernel.
Authors put any expected output directly into the Markdown (as
plain prose or as ` ```text ` blocks), and the HTML just renders
what's there.

Lean code blocks become syntax-highlighted `<pre><code>` (we use
the `language-lean` class so highlight.js picks them up if the
page wants to include the script; without the script the block is
still readable, just monochrome).

The Markdown→HTML renderer is intentionally minimal: just enough
to render the tutorial chapters cleanly. It covers:

  * ATX headings `#`, `##`, …
  * fenced code blocks (already split out as separate cells, so
    here we only see *inline* ` ```text ` etc. that survived
    inside Markdown cells)
  * bullet lists (`-` / `*`)
  * blockquotes `>`
  * paragraphs (blank-line separated)
  * inline `code`, **bold**, *italic*, [links](url)
  * raw `<table>` / `<img>` passes through

Anything more exotic (footnotes, definition lists, …) falls
through as a literal paragraph. The chapters under
`docs/tutorial/md/` (and downstream tutorial trees) do not use those features.
-/

/-- HTML-escape a string for embedding in text content. -/
private def escHtml (s : String) : String :=
  s.foldl (init := "") fun acc c =>
    match c with
    | '&' => acc ++ "&amp;"
    | '<' => acc ++ "&lt;"
    | '>' => acc ++ "&gt;"
    | '"' => acc ++ "&quot;"
    | _   => acc.push c

/-- Render inline Markdown: `code`, **bold**, *italic*, [text](url).
    Order matters — code spans first so we don't accidentally
    emphasise an underscore inside one. -/
private partial def renderInline (s : String) : String :=
  goCode s.toList "" |>.fst
where
  /-- Walk characters, peeling off `` `code` `` spans first. The
      remaining text is sent through `goEmph`. -/
  goCode : List Char → String → String × Unit
    | [], acc => (acc, ())
    | '`' :: rest, acc =>
      let (inside, after) := rest.span (· ≠ '`')
      match after with
      | '`' :: tail =>
        let span := "<code>" ++ escHtml (String.mk inside) ++ "</code>"
        goCode tail (acc ++ span)
      | _ =>
        -- Unmatched backtick: treat as literal.
        goCode rest (acc ++ "`")
    | c :: rest, acc =>
      -- Emph / link handling on `[c]++rest` collectively.
      let (consumed, html, newRest) := tryLinkOrEmph c rest
      if consumed then goCode newRest (acc ++ html)
      else goCode rest (acc ++ escHtml (String.mk [c]))
  /-- Try to consume a [link](url), **bold**, or *italic* starting
      at `c :: rest`. Returns (consumed?, html, remaining). -/
  tryLinkOrEmph (c : Char) (rest : List Char) : Bool × String × List Char :=
    if c == '[' then
      let (text, after1) := rest.span (· ≠ ']')
      match after1 with
      | ']' :: '(' :: tail =>
        let (url, after2) := tail.span (· ≠ ')')
        match after2 with
        | ')' :: tail2 =>
          let html := "<a href=\"" ++ escHtml (String.mk url) ++ "\">"
            ++ escHtml (String.mk text) ++ "</a>"
          (true, html, tail2)
        | _ => (false, "", rest)
      | _ => (false, "", rest)
    else if c == '*' then
      match rest with
      | '*' :: tail =>
        -- bold **...**
        let (inner, after) := splitDoubleStar tail
        match after with
        | some tail2 =>
          (true, "<strong>" ++ escHtml (String.mk inner) ++ "</strong>", tail2)
        | none => (false, "", rest)
      | _ =>
        -- italic *...*
        let (inner, after) := rest.span (· ≠ '*')
        match after with
        | '*' :: tail =>
          (true, "<em>" ++ escHtml (String.mk inner) ++ "</em>", tail)
        | _ => (false, "", rest)
    else
      (false, "", rest)
  /-- Find the next `**` and return the chars before it and the
      tail after the `**`, if any. -/
  splitDoubleStar : List Char → List Char × Option (List Char)
    | [] => ([], none)
    | '*' :: '*' :: tail => ([], some tail)
    | c :: rest =>
      let (inner, after) := splitDoubleStar rest
      (c :: inner, after)

/-- Render a Markdown cell body to HTML.  Operates block-by-block. -/
private def renderMarkdownBlock (lines : Array String) : String := Id.run do
  let n := lines.size
  let mut i := 0
  let mut out := ""
  while i < n do
    let line := lines[i]!
    let trimmed := line.trimAsciiStart.toString
    if line.isEmpty then
      i := i + 1
    else if trimmed.startsWith "# " then
      out := out ++ "<h1>" ++ renderInline (trimmed.drop 2).toString ++ "</h1>\n"
      i := i + 1
    else if trimmed.startsWith "## " then
      out := out ++ "<h2>" ++ renderInline (trimmed.drop 3).toString ++ "</h2>\n"
      i := i + 1
    else if trimmed.startsWith "### " then
      out := out ++ "<h3>" ++ renderInline (trimmed.drop 4).toString ++ "</h3>\n"
      i := i + 1
    else if trimmed.startsWith "#### " then
      out := out ++ "<h4>" ++ renderInline (trimmed.drop 5).toString ++ "</h4>\n"
      i := i + 1
    else if trimmed.startsWith "```" then
      -- Inline fenced block (kept inside the Markdown cell — these
      -- are illustrative `text` / `bash` / `verilog` etc. spans).
      let tag := (trimmed.drop 3).trimAscii.toString
      let mut body := ""
      i := i + 1
      while i < n && !(lines[i]!.trimAsciiStart.toString.startsWith "```") do
        body := body ++ escHtml lines[i]! ++ "\n"
        i := i + 1
      if i < n then i := i + 1  -- skip closing fence
      let cls := if tag.isEmpty then "" else " class=\"language-" ++ escHtml tag ++ "\""
      out := out ++ "<pre><code" ++ cls ++ ">" ++ body ++ "</code></pre>\n"
    else if trimmed.startsWith "- " || trimmed.startsWith "* " then
      out := out ++ "<ul>\n"
      while i < n &&
            (lines[i]!.trimAsciiStart.toString.startsWith "- " ||
             lines[i]!.trimAsciiStart.toString.startsWith "* ") do
        let item := (lines[i]!.trimAsciiStart.toString.drop 2).toString
        out := out ++ "  <li>" ++ renderInline item ++ "</li>\n"
        i := i + 1
      out := out ++ "</ul>\n"
    else if trimmed.startsWith "> " then
      out := out ++ "<blockquote>\n"
      while i < n && lines[i]!.trimAsciiStart.toString.startsWith "> " do
        let item := (lines[i]!.trimAsciiStart.toString.drop 2).toString
        out := out ++ renderInline item ++ "<br>\n"
        i := i + 1
      out := out ++ "</blockquote>\n"
    else if trimmed.startsWith "|" && i + 1 < n
            && lines[i+1]!.trimAsciiStart.toString.startsWith "|"
            && (lines[i+1]!.trimAsciiStart.toString.contains '-') then
      -- GitHub-flavoured Markdown table:
      --   | h1 | h2 |
      --   |----|----|
      --   | a  | b  |
      -- Second row is the separator (cells of dashes / colons).
      let splitRow (s : String) : Array String :=
        let t := s.trimAsciiStart.toString
        let t := if t.startsWith "|" then (t.drop 1).toString else t
        let t := if t.endsWith "|" then (t.dropEnd 1).toString else t
        (t.splitOn "|").toArray.map fun c => c.trimAscii.toString
      out := out ++ "<table>\n<thead><tr>"
      for h in splitRow lines[i]! do
        out := out ++ "<th>" ++ renderInline h ++ "</th>"
      out := out ++ "</tr></thead>\n"
      i := i + 2  -- skip header + separator
      out := out ++ "<tbody>\n"
      while i < n && lines[i]!.trimAsciiStart.toString.startsWith "|" do
        out := out ++ "  <tr>"
        for c in splitRow lines[i]! do
          out := out ++ "<td>" ++ renderInline c ++ "</td>"
        out := out ++ "</tr>\n"
        i := i + 1
      out := out ++ "</tbody></table>\n"
    else if trimmed.startsWith "<" then
      -- Raw HTML: pass through untouched (covers images
      -- written inline).
      out := out ++ line ++ "\n"
      i := i + 1
    else
      -- Paragraph: gather consecutive non-blank lines.
      let mut para := ""
      while i < n && !lines[i]!.isEmpty
            && !lines[i]!.trimAsciiStart.toString.startsWith "#"
            && !lines[i]!.trimAsciiStart.toString.startsWith "```"
            && !lines[i]!.trimAsciiStart.toString.startsWith "- "
            && !lines[i]!.trimAsciiStart.toString.startsWith "* "
            && !lines[i]!.trimAsciiStart.toString.startsWith "> "
            && !lines[i]!.trimAsciiStart.toString.startsWith "|" do
        let sep := if para.isEmpty then "" else " "
        para := para ++ sep ++ lines[i]!
        i := i + 1
      out := out ++ "<p>" ++ renderInline para ++ "</p>\n"
  pure out

/-- Render a single CellOutput to HTML.

    Rendering depends on the MIME type:
      * ""              → `<pre class="output">PLAIN</pre>`
      * text/plain+lang → `<pre class="output"><code class="language-LANG">…`
      * text/html       → raw HTML in `<div class="output">…</div>`
      * image/svg+xml   → raw SVG in `<div class="output">…</div>`
      * text/latex      → `<div class="output">$…$</div>` (MathJax)
      * text/markdown   → recursively rendered as a markdown block
      * application/json → `<pre class="output"><code class="language-json">…` -/
private def outputToHtml (o : CellOutput) : String :=
  let body := o.lines.foldl (init := "") fun acc l => acc ++ l ++ "\n"
  match o.mime with
  | "" =>
    "<pre class=\"output\">" ++ escHtml body ++ "</pre>\n"
  | "text/plain" =>
    let cls := if o.language.isEmpty then ""
               else " class=\"language-" ++ escHtml o.language ++ "\""
    "<pre class=\"output\"><code" ++ cls ++ ">" ++ escHtml body ++ "</code></pre>\n"
  | "application/json" =>
    "<pre class=\"output\"><code class=\"language-json\">"
      ++ escHtml body ++ "</code></pre>\n"
  | "text/html" =>
    "<div class=\"output html\">\n" ++ body ++ "\n</div>\n"
  | "image/svg+xml" =>
    "<div class=\"output svg\">\n" ++ body ++ "\n</div>\n"
  | "text/latex" =>
    -- Pass through verbatim; MathJax (if loaded) renders the
    -- `$...$` / `\(...\)` markers.
    "<div class=\"output latex\">\n" ++ body ++ "\n</div>\n"
  | "text/markdown" =>
    "<div class=\"output md\">\n"
      ++ renderMarkdownBlock o.lines ++ "</div>\n"
  | other =>
    -- Unknown mime: show as escaped text with the mime as label.
    "<pre class=\"output\" data-mime=\"" ++ escHtml other ++ "\">"
      ++ escHtml body ++ "</pre>\n"

/-- Render a single cell to the body HTML used inside a chapter
    page.  Code cells use a `language-lean` class so highlight.js
    can colour them if the page loads it; their outputs are
    rendered below in `<div class="output …">` containers. -/
private def cellToHtml : Cell → String
  | .markdown ls => renderMarkdownBlock ls
  | .code ls outs =>
    let body := ls.foldl (fun acc l => acc ++ escHtml l ++ "\n") ""
    let codeHtml := "<pre><code class=\"language-lean\">" ++ body ++ "</code></pre>\n"
    let outHtml := outs.foldl (init := "") fun acc o => acc ++ outputToHtml o
    codeHtml ++ outHtml

/-- Extract the first H1 in a cells list, for use as the chapter
    title.  Falls back to the first non-empty line of the first
    Markdown cell, or "Untitled". -/
def chapterTitle (cells : Array Cell) : String := Id.run do
  for c in cells do
    match c with
    | .markdown ls =>
      for l in ls do
        let t := l.trimAsciiStart.toString
        if t.startsWith "# " then return (t.drop 2).trimAscii.toString
      -- No H1: first non-empty line.
      for l in ls do
        if !l.isEmpty then return l
    | _ => pure ()
  pure "Untitled"

/-- Strip the "Chapter N — " prefix from a chapter title so the
    sidebar / nav can show just the short subtitle.  Returns
    `(numberPart, shortTitle)` where `numberPart` is "0" / "1b"
    etc. when present, "" otherwise, and `shortTitle` is the rest.

    Recognised prefixes (case-insensitive on "chapter"):
      "Chapter 0 — Setup"            → ("0",  "Setup")
      "Chapter 1b — Your First …"    → ("1b", "Your First …")
      "Plain title with no chapter"  → ("",   "Plain title with no chapter")
    Em-dash and ASCII dash both accepted; any spaces around the
    dash are eaten. -/
def stripChapterPrefix (title : String) : String × String := Id.run do
  let t := title.trimAscii.toString
  let lower := t.toLower
  if !lower.startsWith "chapter " then return ("", t)
  let rest := (t.drop 8).trimAsciiStart.toString  -- after "Chapter "
  -- Take the number/identifier (digits + optional letter suffix).
  let cs := rest.toList
  let isNumLike (c : Char) := c.isDigit || c.isAlpha
  let (numChars, after) := cs.span isNumLike
  if numChars.isEmpty then return ("", t)
  let numPart := String.ofList numChars
  -- Eat whitespace, then a dash (— or --- or -), then whitespace.
  let afterTrimmed := (String.ofList after).trimAsciiStart.toString
  let body : String :=
    if afterTrimmed.startsWith "—" then
      (afterTrimmed.drop 1).trimAsciiStart.toString
    else if afterTrimmed.startsWith "–" then
      (afterTrimmed.drop 1).trimAsciiStart.toString
    else if afterTrimmed.startsWith "-" then
      (afterTrimmed.drop 1).trimAsciiStart.toString
    else
      -- No dash: the title was something like "Chapter 0" with
      -- nothing after.  Keep it as-is so we still show *something*.
      afterTrimmed
  if body.isEmpty then return ("", t)
  pure (numPart, body)

/-- HTML preamble shared by every chapter page.  Loads highlight.js
    plus the third-party `highlightjs-lean` language definition so
    `<pre><code class="language-lean">` blocks pick up real Lean
    keywords (def, fun, match, etc.).  Pages still render fine if
    the CDNs are unreachable — they just appear monochrome. -/
private def htmlHead (title : String) (relRoot : String) : String :=
  "<!doctype html>\n" ++
  "<html lang=\"en\"><head>\n" ++
  "<meta charset=\"utf-8\">\n" ++
  "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n" ++
  "<title>" ++ escHtml title ++ "</title>\n" ++
  "<link rel=\"stylesheet\" href=\"" ++ relRoot ++ "style.css\">\n" ++
  "<link rel=\"stylesheet\" href=\"https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@11.9.0/build/styles/github.min.css\">\n" ++
  "<script src=\"https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@11.9.0/build/highlight.min.js\"></script>\n" ++
  -- highlightjs-lean self-registers `lean` with hljs on load, so
  -- `<pre><code class=\"language-lean\">` blocks pick up real Lean
  -- keywords (def, theorem, fun, match, …) instead of being
  -- auto-detected as something else.
  "<script src=\"https://cdn.jsdelivr.net/npm/highlightjs-lean@1.0.0/dist/lean.min.js\"></script>\n" ++
  "<script>document.addEventListener('DOMContentLoaded',function(){hljs.highlightAll();});</script>\n" ++
  "</head><body>\n"

private def htmlFoot : String := "</body></html>\n"

/-- Render the sidebar nav (left column).  Highlights `current`.

    Strips the "Chapter N — " prefix from each entry so the
    sidebar reads as a compact "N. Short title" list. -/
def renderSidebar (siteTitle : String)
    (chapters : Array (String × String))
    (current : Option String) : String :=
  let items := chapters.foldl (init := "") fun acc (file, title) =>
    let cls := if current == some file then " class=\"active\"" else ""
    let (num, short) := stripChapterPrefix title
    let label :=
      if num.isEmpty then escHtml short
      else "<span class=\"chnum\">" ++ escHtml num ++ "</span> "
           ++ escHtml short
    acc ++ "    <li" ++ cls ++ "><a href=\"" ++ escHtml file ++ "\">"
        ++ label ++ "</a></li>\n"
  "<aside class=\"sidebar\">\n" ++
  "  <a class=\"site-title\" href=\"index.html\">" ++ escHtml siteTitle ++ "</a>\n" ++
  "  <ul class=\"toc\">\n" ++ items ++ "  </ul>\n" ++
  "</aside>\n"

/-- Default stylesheet served alongside the chapter pages.  Two-
    column layout: fixed sidebar on the left, scrollable main
    column on the right.  Collapses to a stacked single-column
    layout under 800px. -/
def defaultStylesheet : String :=
  ":root { color-scheme: light dark; }\n" ++
  "* { box-sizing: border-box; }\n" ++
  "body { margin: 0;\n" ++
  "       font-family: -apple-system, BlinkMacSystemFont, Helvetica, Arial, sans-serif;\n" ++
  "       line-height: 1.55; color: #222; background: #fff; }\n" ++
  ".layout { display: flex; min-height: 100vh; }\n" ++
  "aside.sidebar {\n" ++
  "  width: 280px; flex-shrink: 0; background: #0d47a1; color: #fff;\n" ++
  "  padding: 1.5em 0; overflow-y: auto; position: sticky; top: 0;\n" ++
  "  height: 100vh;\n" ++
  "}\n" ++
  "aside.sidebar .site-title {\n" ++
  "  display: block; padding: 0 1.2em 1em; font-size: 1.1em;\n" ++
  "  font-weight: 600; color: #fff; text-decoration: none;\n" ++
  "  border-bottom: 1px solid rgba(255,255,255,0.15);\n" ++
  "  margin-bottom: 0.6em;\n" ++
  "}\n" ++
  "aside.sidebar ul.toc { list-style: none; padding: 0; margin: 0; }\n" ++
  "aside.sidebar ul.toc li a {\n" ++
  "  display: block; padding: 0.55em 1.2em; color: rgba(255,255,255,0.85);\n" ++
  "  text-decoration: none; font-size: 0.92em; border-left: 3px solid transparent;\n" ++
  "}\n" ++
  "aside.sidebar .chnum {\n" ++
  "  display: inline-block; min-width: 1.7em; margin-right: 0.4em;\n" ++
  "  color: rgba(255,255,255,0.55); font-variant-numeric: tabular-nums;\n" ++
  "  font-size: 0.85em;\n" ++
  "}\n" ++
  "aside.sidebar ul.toc li a:hover {\n" ++
  "  background: rgba(255,255,255,0.08); color: #fff;\n" ++
  "}\n" ++
  "aside.sidebar ul.toc li.active a {\n" ++
  "  background: rgba(255,255,255,0.12); color: #fff;\n" ++
  "  border-left-color: #ffca28; font-weight: 500;\n" ++
  "}\n" ++
  "main.content {\n" ++
  "  flex: 1; padding: 2em 3em; max-width: 880px; min-width: 0;\n" ++
  "}\n" ++
  "main.content h1, main.content h2, main.content h3, main.content h4 {\n" ++
  "  line-height: 1.2; margin-top: 1.6em;\n" ++
  "}\n" ++
  "main.content h1 { border-bottom: 2px solid #2196F3; padding-bottom: 0.2em;\n" ++
  "                  margin-top: 0; }\n" ++
  "main.content h2 { border-bottom: 1px solid #ddd; padding-bottom: 0.15em; }\n" ++
  "code { background: #f4f4f4; padding: 1px 4px; border-radius: 3px;\n" ++
  "       font-family: 'SF Mono', Menlo, Consolas, monospace; font-size: 0.92em; }\n" ++
  "pre { background: #f7f7f9; border: 1px solid #e1e1e8; border-radius: 4px;\n" ++
  "      padding: 0.8em 1em; overflow-x: auto; }\n" ++
  "pre code { background: none; padding: 0; font-size: 0.9em; }\n" ++
  "blockquote { border-left: 4px solid #2196F3; margin: 1em 0; padding: 0.5em 1em;\n" ++
  "             background: #f0f7ff; color: #444; }\n" ++
  "main.content a { color: #1565c0; text-decoration: none; }\n" ++
  "main.content a:hover { text-decoration: underline; }\n" ++
  "nav.chapter-nav { display: flex; justify-content: space-between;\n" ++
  "                  margin: 2.5em 0 1em; padding-top: 1em;\n" ++
  "                  border-top: 1px solid #ddd; font-size: 0.95em; }\n" ++
  "nav.chapter-nav a.toc { margin: 0 auto; }\n" ++
  "main.content table { border-collapse: collapse; margin: 1em 0; font-size: 0.93em; }\n" ++
  "main.content th, main.content td { border: 1px solid #ddd; padding: 0.4em 0.8em;\n" ++
  "                                   text-align: left; vertical-align: top; }\n" ++
  "main.content th { background: #f3f6fa; font-weight: 600; }\n" ++
  "main.content tr:nth-child(even) td { background: #fafbfc; }\n" ++
  "main.content ul.toc { list-style: none; padding-left: 0; }\n" ++
  "main.content ul.toc li { padding: 0.3em 0; }\n" ++
  "main.content ul.toc a { font-weight: 500; }\n" ++
  "main.content .chnum { display: inline-block; min-width: 1.8em;\n" ++
  "                       color: #888; font-variant-numeric: tabular-nums;\n" ++
  "                       margin-right: 0.4em; }\n" ++
  -- Output blocks (from ```output / ```output:<mime> fences or
  -- ipynb cell outputs).  Stand out from input code with a left
  -- accent bar and a softer background.
  "main.content pre.output, main.content div.output {\n" ++
  "  background: #fafafa; border-left: 3px solid #bcbcbc;\n" ++
  "  border-top: 0; border-right: 0; border-bottom: 0;\n" ++
  "  border-radius: 0 4px 4px 0; padding: 0.7em 1em;\n" ++
  "  margin: -0.3em 0 1em; font-size: 0.88em;\n" ++
  "}\n" ++
  "main.content pre.output { overflow-x: auto; }\n" ++
  "main.content pre.output code { background: none; font-size: 1em; }\n" ++
  "main.content div.output.html, main.content div.output.svg,\n" ++
  "main.content div.output.latex, main.content div.output.md {\n" ++
  "  font-size: 0.92em;\n" ++
  "}\n" ++
  "main.content div.output.svg svg { max-width: 100%; height: auto; }\n" ++
  -- "Open in JupyterLite" button shown at the top of each
  -- chapter when a runnable notebook exists alongside it.
  "main.content .jlite-bar {\n" ++
  "  margin: 0 0 1.2em; text-align: right;\n" ++
  "}\n" ++
  "main.content a.jlite-btn {\n" ++
  "  display: inline-block; padding: 0.4em 0.9em;\n" ++
  "  background: #ffca28; color: #000; border-radius: 4px;\n" ++
  "  font-size: 0.85em; font-weight: 500; text-decoration: none;\n" ++
  "}\n" ++
  "main.content a.jlite-btn:hover { background: #ffb300; text-decoration: none; }\n" ++
  "@media (max-width: 800px) {\n" ++
  "  .layout { flex-direction: column; }\n" ++
  "  aside.sidebar { width: 100%; height: auto; position: static; padding: 1em 0; }\n" ++
  "  main.content { padding: 1.5em 1em; }\n" ++
  "}\n"

/-- Render one chapter to a complete HTML document.

    `sidebar` is the optional sidebar nav (built by the site-mode
    driver from the full chapter list).  When omitted, the page is
    a single-column layout suitable for standalone `--to html`.
    `prev?` / `next?` are filenames (e.g. "Ch00.html") used for
    the navigation footer; `relRoot` is the path prefix from this
    page to the site root (typically "./").

    `jupyterliteUrl?` is an optional URL that opens this chapter's
    runnable notebook in JupyterLite — rendered as an "Open in
    JupyterLite ↗" button next to the chapter title.  Skip it for
    pages that don't have a corresponding live notebook. -/
def cellsToHtml (cells : Array Cell)
    (title : Option String := none)
    (prev? : Option (String × String) := none)
    (next? : Option (String × String) := none)
    (relRoot : String := "./")
    (sidebar : String := "")
    (jupyterliteUrl? : Option String := none) : String :=
  let actualTitle := title.getD (chapterTitle cells)
  let body := cells.foldl (fun acc c => acc ++ cellToHtml c) ""
  let navLink : Option (String × String) → String → String := fun p arrow =>
    match p with
    | some (file, t) =>
      -- Drop the "Chapter N — " prefix; the arrow plus short
      -- title is what readers actually scan for.
      let (_, short) := stripChapterPrefix t
      "<a href=\"" ++ escHtml file ++ "\">" ++ arrow ++ " " ++ escHtml short ++ "</a>"
    | none => "<span></span>"
  let jliteBar : String :=
    match jupyterliteUrl? with
    | some url =>
      "<div class=\"jlite-bar\">\n" ++
      "<a class=\"jlite-btn\" href=\"" ++ escHtml url ++ "\" target=\"_blank\" rel=\"noopener\">" ++
      "▶ Open this chapter in JupyterLite</a>\n" ++
      "</div>\n"
    | none => ""
  let nav :=
    "<nav class=\"chapter-nav\">\n" ++
    navLink prev? "←" ++ "\n" ++
    "<a class=\"toc\" href=\"" ++ relRoot ++ "index.html\">Contents</a>\n" ++
    navLink next? "→" ++ "\n" ++
    "</nav>\n"
  let content := "<main class=\"content\">\n" ++ jliteBar ++ body ++ nav ++ "</main>\n"
  let inner :=
    if sidebar.isEmpty then content
    else "<div class=\"layout\">\n" ++ sidebar ++ content ++ "</div>\n"
  htmlHead actualTitle relRoot ++ inner ++ htmlFoot

/-- Site index page (the home page).  Lays out a sidebar (same
    one used on every chapter) plus a welcome panel on the right
    that lists the chapters again with their titles. -/
def renderSiteIndex (siteTitle : String)
    (chapters : Array (String × String))
    (intro : String := "") : String :=
  let sidebar := renderSidebar siteTitle chapters (current := some "index.html")
  let chapterList := chapters.foldl (init := "") fun acc (file, title) =>
    let (num, short) := stripChapterPrefix title
    let label :=
      if num.isEmpty then escHtml short
      else "<span class=\"chnum\">" ++ escHtml num ++ "</span> "
           ++ escHtml short
    acc ++ "  <li><a href=\"" ++ escHtml file ++ "\">" ++ label ++ "</a></li>\n"
  let introBlock :=
    if intro.isEmpty then ""
    else "<p class=\"intro\">" ++ escHtml intro ++ "</p>\n"
  let content :=
    "<main class=\"content\">\n" ++
    "<h1>" ++ escHtml siteTitle ++ "</h1>\n" ++
    introBlock ++
    "<h2>Chapters</h2>\n" ++
    "<ul class=\"toc\">\n" ++ chapterList ++ "</ul>\n" ++
    "</main>\n"
  htmlHead siteTitle "./" ++
  "<div class=\"layout\">\n" ++ sidebar ++ content ++ "</div>\n" ++
  htmlFoot

/-! ## 6. ipynb → cells (reverse direction)

This lets a user round-trip:
    .md  -- xlean-convert --to ipynb -->  .ipynb  (run in Jupyter)
    .ipynb  -- xlean-convert --to md -->  .md  (with outputs baked in)

After the second leg the Markdown source carries every cell's
evaluated output as ` ```output[:MIME] ` fences below the code,
so the file is git-diff-friendly and renders with results when
passed through `--to html`.
-/

open Lean (FromJson)

/-- Parse a Jupyter ipynb document into our cell representation.
    Recognises the same MIME types that `outputToHtml` knows how
    to render; everything else falls through as a plain-text
    output tagged with its mime type as a language hint. -/
def parseIpynb (src : String) : Except String (Array Cell) := do
  let json ← Json.parse src
  let nb := json
  let cellsJson ← nb.getObjValAs? (Array Json) "cells"
  let mut out : Array Cell := Array.mkEmpty cellsJson.size
  for cj in cellsJson do
    let ctype ← cj.getObjValAs? String "cell_type"
    -- Source can be a string or an array of strings.
    let srcLines : Array String ←
      match cj.getObjVal? "source" with
      | .ok (.str s)  => pure (s.splitOn "\n").toArray
      | .ok (.arr arr) =>
        pure <| arr.map fun j =>
          match j with | .str s => s | _ => ""
      | _ => pure #[]
    -- Strip a single trailing "\n" from each array entry (ipynb
    -- convention) and re-split on any embedded newlines.
    let normLines (ls : Array String) : Array String := Id.run do
      let mut acc : Array String := #[]
      for l in ls do
        let l := if l.endsWith "\n" then l.dropEnd 1 |>.toString else l
        for piece in l.splitOn "\n" do
          acc := acc.push piece
      pure acc
    let body := normLines srcLines
    match ctype with
    | "markdown" =>
      out := out.push (.markdown body)
    | "code" | "raw" =>
      -- Pull outputs (only meaningful for code cells; raw cells
      -- typically have none).
      let outsJson : Array Json :=
        match cj.getObjVal? "outputs" with
        | .ok (.arr a) => a
        | _            => #[]
      let mut outs : Array CellOutput := #[]
      for oj in outsJson do
        let otype := (oj.getObjValAs? String "output_type").toOption.getD ""
        match otype with
        | "stream" =>
          let text : Array String ←
            match oj.getObjVal? "text" with
            | .ok (.str s)  => pure (s.splitOn "\n").toArray
            | .ok (.arr a)  => pure <| a.map fun j =>
              match j with | .str s => s | _ => ""
            | _ => pure #[]
          outs := outs.push { mime := "", lines := normLines text }
        | "execute_result" | "display_data" =>
          let dataObj : Json :=
            (oj.getObjVal? "data").toOption.getD (Json.mkObj [])
          let metaObj : Json :=
            (oj.getObjVal? "metadata").toOption.getD (Json.mkObj [])
          let xleanLang : String :=
            (metaObj.getObjValAs? String "xleanLanguage").toOption.getD ""
          -- Pick the most informative MIME type available, in
          -- this preference order:
          let prefs := #[
            "image/svg+xml", "text/html", "text/latex",
            "text/markdown", "application/json", "text/plain"]
          let mut picked : Option (String × Array String) := none
          for m in prefs do
            if picked.isSome then continue
            match dataObj.getObjVal? m with
            | .ok (.str s) =>
              picked := some (m, (s.splitOn "\n").toArray)
            | .ok (.arr a) =>
              let ls := a.map fun j =>
                match j with | .str s => s | _ => ""
              picked := some (m, ls)
            | _ => pure ()
          match picked with
          | some (m, ls) =>
            outs := outs.push
              { mime := m, language := xleanLang, lines := normLines ls }
          | none => pure ()
        | "error" =>
          -- Render error tracebacks as a plain-text stream-style
          -- output so they survive the round-trip.
          let tb : Array String :=
            match oj.getObjVal? "traceback" with
            | .ok (.arr a) => a.map fun j =>
              match j with | .str s => s | _ => ""
            | _ => #[]
          outs := outs.push { mime := "", lines := normLines tb }
        | _ => pure ()
      out := out.push (.code body outs)
    | _ =>
      -- Unknown cell_type: drop.
      pure ()
  return out

/-! ## 7. Cells → Markdown (with `output:*` fences) -/

/-- Render a CellOutput as a ` ```output[:MIME] ` fence. -/
private def outputToMd (o : CellOutput) : String :=
  let tag : String :=
    if o.mime.isEmpty then "output"
    else
      match o.mime with
      | "text/html"        => "output:html"
      | "image/svg+xml"    => "output:svg"
      | "text/latex"       => "output:latex"
      | "text/markdown"    => "output:md"
      | "application/json" => "output:json"
      | "text/plain"       =>
        if o.language.isEmpty then "output:plain"
        else "output:" ++ o.language
      | other => "output:" ++ other
  let body := o.lines.foldl (init := "") fun acc l => acc ++ l ++ "\n"
  "```" ++ tag ++ "\n" ++ body ++ "```\n"

/-- Render one cell as Markdown.  Code cells become ` ```lean `
    fences followed by zero or more ` ```output[:MIME] ` fences. -/
private def cellToMd : Cell → String
  | .markdown ls =>
    -- Markdown cells just dump their lines back verbatim.
    let body := ls.foldl (init := "") fun acc l => acc ++ l ++ "\n"
    body
  | .code ls outs =>
    let body := ls.foldl (init := "") fun acc l => acc ++ l ++ "\n"
    let outBlocks := outs.foldl (init := "") fun acc o => acc ++ outputToMd o
    "```lean\n" ++ body ++ "```\n" ++ outBlocks

/-- Serialise cells back to Markdown.  Cells are separated by a
    blank line so the result is easy to diff. -/
def cellsToMarkdown (cells : Array Cell) : String :=
  let parts := cells.map cellToMd
  parts.foldl (init := "") fun acc s =>
    if acc.isEmpty then s
    else
      -- Ensure exactly one blank line between cells.
      let prev := if acc.endsWith "\n" then acc else acc ++ "\n"
      prev ++ "\n" ++ s

/-! ## 8. Cells → Lean source for batch evaluation

The "eval" pipeline:
  1. `renderForEval`  : cells → one .lean file with cell delimiters
  2. (caller runs `lean --run` on the file, captures stdout)
  3. `parseEvalOutput`: stdout → updated cells with outputs attached

The delimiter convention is a line like
    ===XLEAN-CELL-END n===
emitted after every code cell.  Everything between two delimiters
(or between the start of stdout and the first delimiter) belongs
to cell n.  Inside a cell's text we then look for Display's MIME
markers (\x1bMIME:<type>\x1e<body>\x1b/MIME\x1e); whatever is
outside markers becomes a plain stream output.
-/

/-- Cell-end marker prefix (followed by index, then `===\n`). -/
private def cellEndPrefix : String := "===XLEAN-CELL-END "

/-- Render the cell sequence as a single .lean file that, when
    run with `lean --run`, prints each code cell's plain stdout
    followed by a delimiter so we can split the stream back into
    per-cell outputs.

    Caller must ensure that `Display` is available on the LEAN_PATH;
    a typical setup script imports the necessary modules at the top
    of `header` (a verbatim prelude). -/
def renderForEval (cells : Array Cell) (header : String := "import Display\n\n") : String := Id.run do
  -- First pass: hoist every `import …` line from every code cell to
  -- the top of the file.  Lean rejects mid-file imports, so chapters
  -- that introduce a new Mathlib module partway through (which is
  -- the natural way to write a tutorial — "let's now bring in
  -- Mathlib.Analysis…") would otherwise fail with
  --   error: invalid 'import' command, it must be used in the
  --   beginning of the file
  -- Hoisting is order-preserving: imports keep their original
  -- relative order, so any module that depends on a sibling still
  -- sees it loaded first.
  let mut imports : Array String := #[]
  let mut seen : Std.HashSet String := {}
  for c in cells do
    match c with
    | .markdown _ => pure ()
    | .code ls _ =>
      for l in ls do
        let trimmed := l.trim
        if trimmed.startsWith "import " && !(seen.contains trimmed) then
          imports := imports.push trimmed
          seen := seen.insert trimmed

  let mut out := header
  for imp in imports do
    out := out ++ imp ++ "\n"
  if !imports.isEmpty then
    out := out ++ "\n"

  -- Second pass: emit the rest of every cell, dropping the imports
  -- we already hoisted.  Cell delimiters still fire so the output
  -- splitter in attachEvalOutputs lines up with the original cells.
  let mut idx := 0
  for c in cells do
    match c with
    | .markdown _ => pure ()
    | .code ls _ =>
      for l in ls do
        let trimmed := l.trim
        if !(trimmed.startsWith "import ") then
          out := out ++ l ++ "\n"
      out := out ++ s!"#eval show IO Unit from do\n"
                 ++ s!"  let mimes ← Display.drain\n"
                 ++ s!"  IO.print mimes\n"
                 ++ s!"  IO.println \"{cellEndPrefix}{idx}===\"\n"
      idx := idx + 1
  pure out

/-- Strip ANSI MIME markers from `text`, returning the leftover
    plain text plus an array of `(mime, body)` pairs.  Same wire
    format as Display.emit / xeus_ffi.cpp:extract_mime_payloads.

    Works on `List Char` rather than String.Pos to avoid String.Pos
    arithmetic quirks; the documents we feed in are at most a few
    MB so this is fine. -/
private def extractMimePayloads (text : String) : String × Array (String × String) := Id.run do
  let esc := Char.ofNat 0x1B
  let rs  := Char.ofNat 0x1E
  let mut plain : String := ""
  let mut bundles : Array (String × String) := #[]
  let mut cs := text.toList
  while !cs.isEmpty do
    match cs with
    | c :: rest =>
      if c == esc then
        -- Try to match `\x1bMIME:<type>\x1e<body>\x1b/MIME\x1e`.
        match rest with
        | 'M' :: 'I' :: 'M' :: 'E' :: ':' :: after =>
          let (mimeChars, afterMime) := after.span (· ≠ rs)
          match afterMime with
          | _rs :: bodyChars =>
            -- Find the closing `\x1b/MIME\x1e`.
            let closing := [esc, '/', 'M', 'I', 'M', 'E', rs]
            let rec splitAt (acc : List Char) (xs : List Char) : Option (List Char × List Char) :=
              if closing.isPrefixOf xs then some (acc.reverse, xs.drop closing.length)
              else
                match xs with
                | [] => none
                | y :: ys => splitAt (y :: acc) ys
            match splitAt [] bodyChars with
            | some (body, tail) =>
              bundles := bundles.push (String.mk mimeChars, String.mk body)
              cs := tail
            | none =>
              plain := plain.push c
              cs := rest
          | _ =>
            plain := plain.push c
            cs := rest
        | _ =>
          plain := plain.push c
          cs := rest
      else
        plain := plain.push c
        cs := rest
    | [] => cs := []
  pure (plain, bundles)
termination_by text.length

/-- Trim a single trailing `\n` from a string. -/
private def chomp (s : String) : String :=
  if s.endsWith "\n" then s.dropEnd 1 |>.toString else s

/-- Split lines into per-cell chunks using the `cellEndPrefix N`
    delimiter.  Returns `chunks[n] = stdout text emitted by cell n`
    (no trailing newline; the delimiter line itself is dropped). -/
def splitByCellEnd (stdout : String) : Array String := Id.run do
  let mut chunks : Array String := #[]
  let mut buf : String := ""
  for raw in stdout.splitOn "\n" do
    if raw.startsWith cellEndPrefix && raw.endsWith "===" then
      chunks := chunks.push buf
      buf := ""
    else
      buf := if buf.isEmpty then raw else buf ++ "\n" ++ raw
  -- Anything after the last delimiter is dropped (no cell to own it).
  pure chunks

/-- Attach evaluated stdout to the corresponding code cells.

    Walks `cells` left-to-right; each code cell consumes the next
    chunk in `chunks` and gets its outputs replaced.  Markdown cells
    pass through unchanged.

    If `chunks` is shorter than the number of code cells (e.g. an
    earlier cell errored and aborted execution), later cells keep
    their existing outputs.  If longer, extra chunks are dropped. -/
def attachEvalOutputs (cells : Array Cell) (chunks : Array String) : Array Cell := Id.run do
  let mut out : Array Cell := Array.mkEmpty cells.size
  let mut chunkIdx := 0
  for c in cells do
    match c with
    | .markdown _ => out := out.push c
    | .code src _ =>
      if h : chunkIdx < chunks.size then
        let chunk := chunks[chunkIdx]
        let (plain, bundles) := extractMimePayloads chunk
        let plain := chomp plain
        let mut newOuts : Array CellOutput := #[]
        if !plain.isEmpty then
          newOuts := newOuts.push
            { mime := "", lines := (plain.splitOn "\n").toArray }
        for (mime, body) in bundles do
          newOuts := newOuts.push
            { mime := mime, lines := (chomp body).splitOn "\n" |>.toArray }
        out := out.push (.code src newOuts)
        chunkIdx := chunkIdx + 1
      else
        out := out.push c
  pure out

end Convert
