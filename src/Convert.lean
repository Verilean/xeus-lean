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
to render the Sparkle tutorial chapters cleanly. It covers:

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
`Verilean/sparkle/docs/tutorial/md/` do not use those features.
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
    else if trimmed.startsWith "<" then
      -- Raw HTML: pass through untouched (covers tables/images
      -- written inline).
      out := out ++ line ++ "\n"
      i := i + 1
    else
      -- Paragraph: gather consecutive non-blank lines.
      let mut para := ""
      while i < n && !lines[i]!.isEmpty && !lines[i]!.trimAsciiStart.toString.startsWith "#"
            && !lines[i]!.trimAsciiStart.toString.startsWith "```"
            && !lines[i]!.trimAsciiStart.toString.startsWith "- "
            && !lines[i]!.trimAsciiStart.toString.startsWith "* "
            && !lines[i]!.trimAsciiStart.toString.startsWith "> " do
        let sep := if para.isEmpty then "" else " "
        para := para ++ sep ++ lines[i]!
        i := i + 1
      out := out ++ "<p>" ++ renderInline para ++ "</p>\n"
  pure out

/-- Render a single cell to the body HTML used inside a chapter
    page.  Code cells use a `language-lean` class so highlight.js
    can colour them if the page loads it. -/
private def cellToHtml : Cell → String
  | .markdown ls => renderMarkdownBlock ls
  | .code ls =>
    let body := ls.foldl (fun acc l => acc ++ escHtml l ++ "\n") ""
    "<pre><code class=\"language-lean\">" ++ body ++ "</code></pre>\n"

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

/-- HTML preamble shared by every chapter page.  Loads highlight.js
    from a CDN for Lean syntax colouring; pages still render fine
    if the CDN is unreachable. -/
private def htmlHead (title : String) (relRoot : String) : String :=
  "<!doctype html>\n" ++
  "<html lang=\"en\"><head>\n" ++
  "<meta charset=\"utf-8\">\n" ++
  "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n" ++
  "<title>" ++ escHtml title ++ "</title>\n" ++
  "<link rel=\"stylesheet\" href=\"" ++ relRoot ++ "style.css\">\n" ++
  "<link rel=\"stylesheet\" href=\"https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@11.9.0/build/styles/github.min.css\">\n" ++
  "<script src=\"https://cdn.jsdelivr.net/gh/highlightjs/cdn-release@11.9.0/build/highlight.min.js\"></script>\n" ++
  "<script>document.addEventListener('DOMContentLoaded',function(){hljs.highlightAll();});</script>\n" ++
  "</head><body>\n"

private def htmlFoot : String := "</body></html>\n"

/-- Default stylesheet served alongside the chapter pages. -/
def defaultStylesheet : String :=
  ":root { color-scheme: light dark; }\n" ++
  "body { font-family: -apple-system, BlinkMacSystemFont, Helvetica, Arial, sans-serif;\n" ++
  "       max-width: 820px; margin: 2em auto; padding: 0 1em;\n" ++
  "       line-height: 1.55; color: #222; }\n" ++
  "h1, h2, h3, h4 { line-height: 1.2; margin-top: 1.6em; }\n" ++
  "h1 { border-bottom: 2px solid #2196F3; padding-bottom: 0.2em; }\n" ++
  "h2 { border-bottom: 1px solid #ddd; padding-bottom: 0.15em; }\n" ++
  "code { background: #f4f4f4; padding: 1px 4px; border-radius: 3px;\n" ++
  "       font-family: 'SF Mono', Menlo, Consolas, monospace; font-size: 0.92em; }\n" ++
  "pre { background: #f7f7f9; border: 1px solid #e1e1e8; border-radius: 4px;\n" ++
  "      padding: 0.8em 1em; overflow-x: auto; }\n" ++
  "pre code { background: none; padding: 0; font-size: 0.9em; }\n" ++
  "blockquote { border-left: 4px solid #2196F3; margin: 1em 0; padding: 0.5em 1em;\n" ++
  "             background: #f0f7ff; color: #444; }\n" ++
  "a { color: #1565c0; text-decoration: none; }\n" ++
  "a:hover { text-decoration: underline; }\n" ++
  "nav.chapter-nav { display: flex; justify-content: space-between;\n" ++
  "                  margin: 2em 0 1em; padding-top: 1em;\n" ++
  "                  border-top: 1px solid #ddd; font-size: 0.95em; }\n" ++
  "nav.chapter-nav a.toc { margin: 0 auto; }\n" ++
  "ul.toc { list-style: none; padding-left: 0; }\n" ++
  "ul.toc li { padding: 0.3em 0; }\n" ++
  "ul.toc a { font-weight: 500; }\n"

/-- Render one chapter to a complete HTML document.

    `prev?` / `next?` are filenames (e.g. "Ch00.html") used for
    the navigation footer; `relRoot` is the path prefix from this
    page to the site root (typically "./"). -/
def cellsToHtml (cells : Array Cell)
    (title : Option String := none)
    (prev? : Option (String × String) := none)
    (next? : Option (String × String) := none)
    (relRoot : String := "./") : String :=
  let actualTitle := title.getD (chapterTitle cells)
  let body := cells.foldl (fun acc c => acc ++ cellToHtml c) ""
  let navLink : Option (String × String) → String → String := fun p label =>
    match p with
    | some (file, t) =>
      "<a href=\"" ++ escHtml file ++ "\">" ++ label ++ " " ++ escHtml t ++ "</a>"
    | none => "<span></span>"
  let nav :=
    "<nav class=\"chapter-nav\">\n" ++
    navLink prev? "←" ++ "\n" ++
    "<a class=\"toc\" href=\"" ++ relRoot ++ "index.html\">Contents</a>\n" ++
    navLink next? "→" ++ "\n" ++
    "</nav>\n"
  htmlHead actualTitle relRoot ++ body ++ nav ++ htmlFoot

/-- Build a site index page from a list of (filename, title)
    pairs. -/
def renderSiteIndex (siteTitle : String)
    (chapters : Array (String × String)) : String :=
  let body :=
    "<h1>" ++ escHtml siteTitle ++ "</h1>\n" ++
    "<ul class=\"toc\">\n" ++
    chapters.foldl (init := "") (fun acc (file, title) =>
      acc ++ "  <li><a href=\"" ++ escHtml file ++ "\">"
          ++ escHtml title ++ "</a></li>\n") ++
    "</ul>\n"
  htmlHead siteTitle "./" ++ body ++ htmlFoot

end Convert
