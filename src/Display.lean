/-
Copyright (c) 2025, xeus-lean contributors
Released under Apache 2.0 license as described in the file LICENSE.
-/
import Lean.Elab.Command

/-!
# Rich display support for the xeus-lean Jupyter kernel

This module provides functions and commands for emitting MIME-typed
output (HTML, LaTeX, Markdown, SVG, JSON) that the C++ interpreter
parses and forwards to Jupyter as `display_data` messages.

## Wire format

A rich-display payload is a single line written to stdout with the
following structure:

    \x1bMIME:<mime-type>\x1e<content>\x1b/MIME\x1e

- `\x1b` (ESC, 0x1B) brackets each marker. ESC does not appear in
  ordinary Lean output, so it is safe to use as a sentinel.
- `\x1e` (RS, 0x1E) separates the mime-type from the content and
  terminates the closing marker.
- `<content>` is the raw payload. Newlines inside the content are
  allowed; the C++ side scans for the closing `\x1b/MIME\x1e` marker.

Multiple payloads may be emitted in a single cell; the C++ interpreter
collects them all into one `display_data` MIME bundle.

## Usage

```lean
#html "<b>hello</b>"
#latex "\\int_0^1 x^2 \\, dx = \\frac{1}{3}"
#md "# Title\n**bold** text"
#svg "<svg xmlns='http://www.w3.org/2000/svg' width='40' height='40'><circle cx='20' cy='20' r='18' fill='red'/></svg>"

-- From IO actions:
#eval Display.html "<i>italic</i>"
#eval Display.latex "x^2"
```
-/

namespace Display

/-- Emit a single MIME-typed payload to stdout in the wire format the
    xeus-lean C++ interpreter recognises. -/
def emit (mime : String) (content : String) : IO Unit := do
  let esc := Char.ofNat 0x1B
  let rs  := Char.ofNat 0x1E
  -- Build the marker manually so the ESC/RS bytes are inserted exactly.
  let s := s!"{esc}MIME:{mime}{rs}{content}{esc}/MIME{rs}"
  IO.println s

/-- Display HTML content. -/
def html (content : String) : IO Unit := emit "text/html" content

/-- Display a LaTeX expression. The content should be valid LaTeX
    math (without surrounding `$...$`); JupyterLab renders it via
    MathJax. -/
def latex (content : String) : IO Unit :=
  emit "text/latex" s!"${content}$"

/-- Display a Markdown document. -/
def markdown (content : String) : IO Unit := emit "text/markdown" content

/-- Display an SVG image. -/
def svg (content : String) : IO Unit := emit "image/svg+xml" content

/-- Display a JSON value (as a string). JupyterLab will render it
    using its built-in JSON viewer. -/
def json (content : String) : IO Unit := emit "application/json" content

/-- Display plain text (mostly useful for testing the wire format). -/
def text (content : String) : IO Unit := emit "text/plain" content

end Display

/-! ## Sugar commands

These `#html` / `#latex` / `#md` / `#svg` / `#json` commands expand to
`#eval Display.<kind> <string-literal>`. They keep notebook cells
short and visually distinct from ordinary `#eval`. -/

/-- Display an HTML string. Expands to `#eval Display.html s`. -/
macro "#html " s:str : command => `(#eval Display.html $s)

/-- Display a LaTeX math expression. Expands to `#eval Display.latex s`. -/
macro "#latex " s:str : command => `(#eval Display.latex $s)

/-- Display a Markdown document. Expands to `#eval Display.markdown s`. -/
macro "#md " s:str : command => `(#eval Display.markdown $s)

/-- Display an SVG image. Expands to `#eval Display.svg s`. -/
macro "#svg " s:str : command => `(#eval Display.svg $s)

/-- Display a JSON payload. Expands to `#eval Display.json s`. -/
macro "#json " s:str : command => `(#eval Display.json $s)
