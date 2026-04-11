/-
Copyright (c) 2025, xeus-lean contributors
Released under Apache 2.0 license as described in the file LICENSE.
-/
-- Explicitly import Init so that `import Display` in user cells
-- transitively brings in all of Init (ForIn, do-notation, etc.)
import Init

/-!
# Rich display support for the xeus-lean Jupyter kernel

This module provides functions and commands for emitting MIME-typed
output (HTML, LaTeX, Markdown, SVG, JSON) that the C++ interpreter
parses and forwards to Jupyter as `display_data` messages.

## Wire format

A rich-display payload is encoded as:

    \x1bMIME:<mime-type>\x1e<content>\x1b/MIME\x1e

- `\x1b` (ESC, 0x1B) brackets each marker. ESC does not appear in
  ordinary Lean output, so it is safe to use as a sentinel.
- `\x1e` (RS, 0x1E) separates the mime-type from the content and
  terminates the closing marker.

Multiple payloads may be emitted in a single cell; the C++ interpreter
collects them all into one `display_data` MIME bundle.

## Usage

```lean
#html "<b>hello</b>"
#latex "\\int_0^1 x^2 \\, dx = \\frac{1}{3}"
#md "# Title\n**bold** text"
#svg "<svg xmlns='http://www.w3.org/2000/svg' width='40' height='40'><circle cx='20' cy='20' r='18' fill='red'/></svg>"
```

### Why a custom command and not `#eval Display.html ...`?

In the xeus-lean WASM REPL, `#eval`'s stdout capture does not populate
`Lean.Elab.Command.State.messages`, so `IO.println` from an `#eval`
never reaches the C++ interpreter. The `#html` / `#latex` / ...
commands below instead call `logInfoAt` directly, which writes the
marker straight into the command's `MessageLog`. The REPL returns
those messages verbatim and the C++ side parses the markers out.
-/

namespace Display

/-- Build the MIME wire-format payload. -/
def mkMarker (mime : String) (content : String) : String :=
  let esc := Char.ofNat 0x1B
  let rs  := Char.ofNat 0x1E
  s!"{esc}MIME:{mime}{rs}{content}{esc}/MIME{rs}"

/-- Global buffer for display payloads. WasmRepl.execute drains this
    after each cell execution. -/
initialize displayBuffer : IO.Ref String ← IO.mkRef ""

/-- Append a MIME payload to the global buffer. -/
def emit (mime : String) (content : String) : IO Unit := do
  let marker := mkMarker mime content
  displayBuffer.modify (· ++ marker ++ "\n")

/-- Drain the buffer and return accumulated content (or ""). -/
def drain : IO String := do
  let s ← displayBuffer.get
  displayBuffer.set ""
  return s

def html (content : String) : IO Unit := emit "text/html" content
def latex (content : String) : IO Unit := emit "text/latex" s!"${content}$"
def markdown (content : String) : IO Unit := emit "text/markdown" content
def svg (content : String) : IO Unit := emit "image/svg+xml" content
def json (content : String) : IO Unit := emit "application/json" content

end Display

/-! ## Sugar commands

`#html` / `#latex` / `#md` / `#svg` / `#json` expand to
`#eval Display.<fn> "..."`. The REPL auto-imports `Display` (see
`REPL/Frontend.lean`) so these names resolve in user cells. -/

macro "#html "  s:str : command => `(#eval Display.html $s)
macro "#latex " s:str : command => `(#eval Display.latex $s)
macro "#md "    s:str : command => `(#eval Display.markdown $s)
macro "#svg "   s:str : command => `(#eval Display.svg $s)
macro "#json "  s:str : command => `(#eval Display.json $s)
