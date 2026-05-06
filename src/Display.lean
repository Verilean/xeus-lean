/-
Copyright (c) 2025, xeus-lean contributors
Released under Apache 2.0 license as described in the file LICENSE.
-/
-- Explicitly import Init so that `import Display` in user cells
-- transitively brings in all of Init (ForIn, do-notation, etc.)
import Init
import Lean.Data.Json
import Lean.Elab.Command  -- for `#findDecl` etc. (walks the env)
import CommBus

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

/-- Most recent payload per MIME type, surviving across cells. The
    drain loop empties `displayBuffer` after each cell to ship its
    contents to Jupyter, but `#savefig` needs the underlying bytes
    after that, so we keep a copy here keyed by mime type. -/
initialize lastEmits : IO.Ref (Std.HashMap String String) ← IO.mkRef {}

/-- Append a MIME payload to the global buffer and remember it. -/
def emit (mime : String) (content : String) : IO Unit := do
  let marker := mkMarker mime content
  displayBuffer.modify (· ++ marker ++ "\n")
  lastEmits.modify (·.insert mime content)

/-- Look up the most recent payload of a given MIME type, if any.
    Used by `#savefig` to write the latest figure to a file. -/
def lastEmit? (mime : String) : IO (Option String) := do
  let m ← lastEmits.get
  pure m[mime]?

/-- Drain the buffer and return accumulated content (or ""). -/
def drain : IO String := do
  let s ← displayBuffer.get
  displayBuffer.set ""
  return s

/-- Save the most recent figure to a file. The MIME type to save is
    inferred from the file extension: `.svg → image/svg+xml`,
    `.html → text/html`, `.md → text/markdown`, `.json → application/json`,
    `.tex / .latex → text/latex`. Returns the bytes written, or throws
    if no figure of that type has been emitted in this kernel session. -/
def savefig (path : String) : IO Unit := do
  let mime :=
    if path.endsWith ".svg" then "image/svg+xml"
    else if path.endsWith ".html" then "text/html"
    else if path.endsWith ".md" then "text/markdown"
    else if path.endsWith ".json" then "application/json"
    else if path.endsWith ".tex" || path.endsWith ".latex" then "text/latex"
    else ""
  if mime == "" then
    throw <| IO.userError s!"savefig: cannot infer MIME type from extension of '{path}'"
  match ← lastEmit? mime with
  | none =>
    throw <| IO.userError s!"savefig: no '{mime}' figure has been emitted yet"
  | some content =>
    IO.FS.writeFile path content
    IO.println s!"saved {content.length} bytes to {path}"

def html (content : String) : IO Unit := emit "text/html" content
def latex (content : String) : IO Unit := emit "text/latex" s!"${content}$"
def markdown (content : String) : IO Unit := emit "text/markdown" content
def svg (content : String) : IO Unit := emit "image/svg+xml" content
def json (content : String) : IO Unit := emit "application/json" content

/-- Pretty-print a `BitVec n` as a 3-row HTML table with binary, hex
    and decimal renderings. Useful for sparkle / hardware notebooks
    where you want to eyeball the layout of a register or constant. -/
def bv {n : Nat} (v : BitVec n) : IO Unit := do
  let dec := toString v.toNat
  let hex := s!"0x{(Nat.toDigits 16 v.toNat).asString}"
  -- Binary: pad to width n, MSB first.
  let bin := Id.run do
    let mut s := ""
    for i in [0:n] do
      let bit := (v.toNat >>> (n - 1 - i)) &&& 1
      s := s ++ toString bit
    s
  let html := String.intercalate "" [
    "<table style='font-family:monospace;border-collapse:collapse;font-size:12px;text-align:left'>",
    s!"<tr><td style='padding:2px 8px;color:#888;text-align:left'>bin</td><td style='padding:2px 8px;text-align:left'>{bin}<sub style='color:#888'>{n}</sub></td></tr>",
    s!"<tr><td style='padding:2px 8px;color:#888;text-align:left'>hex</td><td style='padding:2px 8px;text-align:left'>{hex}</td></tr>",
    s!"<tr><td style='padding:2px 8px;color:#888;text-align:left'>dec</td><td style='padding:2px 8px;text-align:left'>{dec}</td></tr>",
    "</table>"
  ]
  emit "text/html" html

/-- Render a list of numeric values as an SVG waveform diagram.
    Each value is drawn as a horizontal bar with height proportional
    to the value, digital-waveform style.

    Parameters:
    - name: signal name label
    - values: list of (Nat) values at consecutive time steps
    - bitWidth: number of bits (for y-axis scaling, default 8)
    - cellW: pixel width per time step (default 40)
    - height: total SVG height (default 80) -/
def waveform (name : String) (values : List Nat)
    (bitWidth : Nat := 8) (cellW : Nat := 40) (height : Nat := 80) : IO Unit := do
  let maxVal := (1 <<< bitWidth) - 1
  let n := values.length
  let w := n * cellW + 80  -- 80px for label
  let labelW := 80
  let plotH := height - 20  -- margin for text
  -- Build SVG path and value labels
  let mut pathD := ""
  let mut labels := ""
  let mut prevY := 0
  let mut idx := 0
  for v in values do
    let x := labelW + idx * cellW
    let y := if maxVal > 0 then plotH - (v * plotH / maxVal) else plotH / 2
    if idx == 0 then
      pathD := pathD ++ s!"M {x} {y}"
    else
      if y != prevY then
        pathD := pathD ++ s!" L {x} {prevY} L {x} {y}"
      else
        pathD := pathD ++ s!" L {x} {y}"
    pathD := pathD ++ s!" L {x + cellW} {y}"
    prevY := y
    let lx := labelW + idx * cellW + cellW / 2
    labels := labels ++ s!"<text x='{lx}' y='{height - 2}' text-anchor='middle' font-size='9' fill='#666'>{v}</text>"
    idx := idx + 1
  -- Grid lines
  let mut grid := ""
  for i in List.range (n + 1) do
    let x := labelW + i * cellW
    grid := grid ++ s!"<line x1='{x}' y1='0' x2='{x}' y2='{plotH}' stroke='#ddd' stroke-width='0.5'/>"
  let svgContent := s!"<svg xmlns='http://www.w3.org/2000/svg' width='{w}' height='{height}'>" ++
    s!"<rect width='{w}' height='{height}' fill='white'/>" ++
    grid ++
    s!"<text x='4' y='{plotH / 2 + 4}' font-size='12' font-family='monospace' fill='#333'>{name}</text>" ++
    s!"<path d='{pathD}' fill='none' stroke='#2196F3' stroke-width='2'/>" ++
    labels ++
    "</svg>"
  emit "image/svg+xml" svgContent

/-- Render N digital lanes stacked on a single SVG.

    Each lane is a `(name, values)` pair where `values : List Bool` is
    sampled at consecutive ticks. All lanes must have the same length;
    if not, the shortest one wins (extra ticks on longer lanes are not
    drawn). Useful for protocol traces (clock + data, parallel bus, ...)
    where you want every lane to share the same time axis.

    Parameters:
    - lanes: list of `(label, samples)` pairs, drawn top-to-bottom
    - cellW: pixel width per tick (default 12)
    - laneH: pixel height per lane (default 30) -/
def boolWave (lanes : List (String × List Bool)) (cellW : Nat := 12)
    (laneH : Nat := 30) : IO Unit := do
  let n := (lanes.head?.map (fun p => p.2.length)).getD 0
  let labelW : Nat := 60
  let totalW : Nat := labelW + n * cellW
  let totalH : Nat := lanes.length * laneH + 8
  let mut body : String := ""
  -- Vertical grid lines (one per tick boundary).
  for i in List.range (n + 1) do
    let x := labelW + i * cellW
    body := body ++ s!"<line x1='{x}' y1='0' x2='{x}' y2='{lanes.length * laneH}' stroke='#eee' stroke-width='0.5'/>"
  let mut idx : Nat := 0
  for (name, vals) in lanes do
    let yTop : Nat := idx * laneH + 4
    let yBot : Nat := idx * laneH + laneH - 6
    body := body ++ s!"<text x='4' y='{yBot - 2}' font-size='11' font-family='monospace' fill='#333'>{name}</text>"
    let mut path : String := ""
    let mut prevY : Nat := yBot
    let mut j : Nat := 0
    for v in vals do
      let x := labelW + j * cellW
      let y := if v then yTop else yBot
      if j == 0 then
        path := path ++ s!"M {x} {y}"
      else if y != prevY then
        path := path ++ s!" L {x} {prevY} L {x} {y}"
      else
        path := path ++ s!" L {x} {y}"
      path := path ++ s!" L {x + cellW} {y}"
      prevY := y
      j := j + 1
    body := body ++ s!"<path d='{path}' fill='none' stroke='#1976d2' stroke-width='2'/>"
    idx := idx + 1
  emit "image/svg+xml" <|
    s!"<svg xmlns='http://www.w3.org/2000/svg' width='{totalW}' height='{totalH}'>" ++
    s!"<rect width='{totalW}' height='{totalH}' fill='white'/>" ++ body ++ "</svg>"

/-- Write a string to a gzip-compressed file by shelling out to the
    system `gzip` binary. Text-form VCD traces in particular compress
    ~10× because they're highly repetitive — a 10 MB VCD becomes a
    1 MB `.vcd.gz`, which GTKWave and Surfer read directly without
    a decompress step. Requires `gzip` on PATH (true in our Docker
    images and any standard Linux/macOS install).

    Implementation: write the plain content to `<filename>.tmp`, then
    `gzip -f <tmp>` which produces `<filename>.tmp.gz`, then rename.
    This avoids piping binary bytes through Lean's UTF-8 String. -/
def writeGz (filename : String) (content : String) : IO Unit := do
  let tmp := filename ++ ".tmp"
  IO.FS.writeFile tmp content
  let out ← IO.Process.output {
    cmd := "gzip", args := #["-f", tmp]
  }
  if out.exitCode != 0 then
    discard <| (IO.FS.removeFile tmp).toBaseIO
    throw <| IO.userError s!"gzip exited with status {out.exitCode}: {out.stderr}"
  -- gzip rewrites tmp → tmp.gz; move that to the requested filename.
  IO.FS.rename (tmp ++ ".gz") filename

/-! ### Hardware block diagrams (`Display.blockDiagram`)

A small structured SVG emitter. Mermaid covers most flowchart needs but
can't draw the canonical EE shapes (trapezoid MUX, real cloud, AND/OR
gates). This emitter fills that gap: nodes are tagged with an EE shape,
edges are typed (data / clock / bus), and a left-to-right layout falls
out of an explicit `col` field on each node so users can compose
diagrams without fighting an autorouter.
-/

inductive NodeKind where
  | port    -- I/O port (parallelogram-ish)
  | reg     -- register / FF (rounded rect)
  | mux     -- multiplexer (trapezoid)
  | cloud   -- combinational logic (cloud-shape)
  | box     -- generic combinational block (rectangle)
  | andG    -- AND gate (D-shape)
  | orG     -- OR gate (shield-shape)
  | notG    -- NOT gate (triangle + bubble)
  | adder   -- adder (circle with +)
  | const   -- constant (small circle)
  | clk     -- clock source (pentagon-ish)
  deriving Inhabited, Repr, BEq

structure DiagNode where
  id     : String
  label  : String
  kind   : NodeKind
  col    : Nat := 0   -- left-to-right column (0 = leftmost)
  row    : Nat := 0   -- top-to-bottom row within the column
  /-- Number of distinct input pins on the left side. Edges target a
      specific pin via `<id>.<n>` syntax in their `dst` field; default
      `inputs := 1` means all incoming edges share one pin. -/
  inputs : Nat := 1
  deriving Inhabited

inductive EdgeKind where
  | data           -- solid arrow
  | clock          -- dashed arrow (clock distribution)
  | bus  (w : Nat) -- thick arrow with bit-width label
  deriving Inhabited, Repr

structure DiagEdge where
  src  : String  -- source node id
  dst  : String  -- destination node id
  kind : EdgeKind := .data
  deriving Inhabited

structure Diagram where
  nodes : List DiagNode
  edges : List DiagEdge
  deriving Inhabited

/-- Pixel dimensions of a node by kind. Hand-tuned to keep typical
    block-diagram element relative sizes recognisable. -/
def NodeKind.size : NodeKind → Nat × Nat
  | .port    => (60, 32)
  | .reg     => (60, 40)
  | .mux     => (50, 60)
  | .cloud   => (90, 60)
  | .box     => (80, 44)
  | .andG    => (60, 44)
  | .orG     => (60, 44)
  | .notG    => (44, 36)
  | .adder   => (36, 36)
  | .const   => (40, 28)
  | .clk     => (50, 36)

/-- SVG primitive for one node, anchored at its top-left `(x, y)`. -/
private def renderNode (n : DiagNode) (x y : Nat) : String :=
  let (w, h) := n.kind.size
  let cx := x + w / 2
  let cy := y + h / 2
  let label :=
    s!"<text x='{cx}' y='{cy + 4}' text-anchor='middle' font-size='11' font-family='monospace' fill='#222'>{n.label}</text>"
  let body := match n.kind with
    | .port =>
      -- parallelogram: (x+8, y) → (x+w, y) → (x+w-8, y+h) → (x, y+h)
      s!"<polygon points='{x+8},{y} {x+w},{y} {x+w-8},{y+h} {x},{y+h}' fill='#fff' stroke='#1565c0' stroke-width='1.5'/>"
    | .reg =>
      s!"<rect x='{x}' y='{y}' width='{w}' height='{h}' rx='4' ry='4' fill='#fff' stroke='#1976d2' stroke-width='2'/>"
    | .mux =>
      -- trapezoid wider on the left (selection in)
      s!"<polygon points='{x},{y} {x+w},{y+h/4} {x+w},{y + 3*h/4} {x},{y+h}' fill='#fff' stroke='#6a1b9a' stroke-width='1.5'/>"
    | .cloud =>
      -- Quick & dirty cloud as 5-arc path. Not pretty but unmistakable.
      let cx0 := x
      let cy0 := y + h/2
      s!"<path d='M {cx0+10} {cy0+10} q -10 -10 5 -20 q 5 -15 25 -10 q 10 -15 30 -5 q 20 -5 25 15 q 15 5 -5 20 z' fill='#fff8e1' stroke='#999' stroke-width='1.2'/>"
    | .box =>
      s!"<rect x='{x}' y='{y}' width='{w}' height='{h}' fill='#fff' stroke='#444' stroke-width='1.5'/>"
    | .andG =>
      -- D-shape: flat left, rounded right
      s!"<path d='M {x} {y} L {x + w/2} {y} A {h/2} {h/2} 0 0 1 {x + w/2} {y+h} L {x} {y+h} z' fill='#fff' stroke='#2e7d32' stroke-width='1.5'/>"
    | .orG =>
      -- Shield-ish: curved back, pointed front
      s!"<path d='M {x} {y} Q {x + w/4} {y + h/2} {x} {y+h} Q {x + 3*w/4} {y + h} {x+w} {y + h/2} Q {x + 3*w/4} {y} {x} {y} z' fill='#fff' stroke='#1565c0' stroke-width='1.5'/>"
    | .notG =>
      let bx := x + w - 6
      let bubY := y + h/2
      s!"<polygon points='{x},{y} {x + w - 12},{y + h/2} {x},{y+h}' fill='#fff' stroke='#c62828' stroke-width='1.5'/>" ++
      s!"<circle cx='{bx}' cy='{bubY}' r='4' fill='#fff' stroke='#c62828' stroke-width='1.5'/>"
    | .adder =>
      s!"<circle cx='{cx}' cy='{cy}' r='{w/2 - 2}' fill='#fff' stroke='#444' stroke-width='1.5'/>" ++
      s!"<line x1='{cx - 8}' y1='{cy}' x2='{cx + 8}' y2='{cy}' stroke='#444' stroke-width='1.5'/>" ++
      s!"<line x1='{cx}' y1='{cy - 8}' x2='{cx}' y2='{cy + 8}' stroke='#444' stroke-width='1.5'/>"
    | .const =>
      s!"<rect x='{x}' y='{y + h/4}' width='{w}' height='{h/2}' rx='10' ry='10' fill='#f5f5f5' stroke='#888'/>"
    | .clk =>
      -- pentagon (clock source flag)
      s!"<polygon points='{x},{y} {x + w - 10},{y} {x+w},{y + h/2} {x + w - 10},{y+h} {x},{y+h}' fill='#fce4ec' stroke='#c2185b' stroke-width='1.5'/>"
  body ++ label

/-- Right-edge anchor (single output) for an edge leaving a node. -/
private def anchorRight (n : DiagNode) (x y : Nat) : Nat × Nat :=
  let (w, h) := n.kind.size
  (x + w, y + h / 2)

/-- Left-edge anchor for the `port`-th input pin (0-indexed). When the
    node has multiple inputs they're distributed evenly along the left
    edge so each incoming wire lands on its own pin. -/
private def anchorLeftPort (n : DiagNode) (x y : Nat) (port : Nat) : Nat × Nat :=
  let (_, h) := n.kind.size
  let inputs := max 1 n.inputs
  -- Evenly spaced pins. With `inputs == 1` this collapses to the
  -- vertical centre, matching the old single-pin behaviour.
  let spacing := h / (inputs + 1)
  let yOff := spacing * (port + 1)
  (x, y + yOff)

/-- Split `"id"` or `"id.port"` into `(id, port)` (port defaults to 0). -/
private def parsePortRef (s : String) : String × Nat :=
  match s.splitOn "." with
  | [id]            => (id, 0)
  | [id, p]         => (id, p.toNat?.getD 0)
  | id :: ps        => (id, (".".intercalate ps).toNat?.getD 0)
  | []              => ("", 0)

/-- Render the whole diagram. Layout:
    * nodes bucketed by `col`, sorted by `row` within each column
    * data + bus edges drawn as smooth Béziers between anchor points
      (output → numbered input pin)
    * clock edges routed through a dedicated rail along the bottom of
      the canvas: drop down from the clock source, run horizontal in
      the rail, climb back up to each destination from below. This
      keeps clock distribution visually distinct from data and prevents
      the clock from crossing data wires that happen to share a row. -/
def blockDiagram (d : Diagram) : IO Unit := do
  let colGap   : Nat := 60
  let rowGap   : Nat := 30
  let pad      : Nat := 20
  let clkRail  : Nat := 24   -- extra space at the bottom for the clock bus
  -- Group nodes by column, sort each column by row
  let mut byCol : Std.HashMap Nat (Array DiagNode) := {}
  for n in d.nodes do
    let arr := byCol.getD n.col #[]
    byCol := byCol.insert n.col (arr.push n)
  let cols := byCol.toList.toArray.qsort (fun (a, _) (b, _) => a < b)
  -- Compute per-node (x, y).
  let mut pos : Std.HashMap String (Nat × Nat) := {}
  let mut x : Nat := pad
  let mut maxY : Nat := pad
  let mut maxX : Nat := pad
  for (_, ns) in cols do
    let sorted := ns.qsort (fun a b => a.row < b.row)
    let colW := sorted.foldl (fun acc n => max acc n.kind.size.1) 0
    let mut y : Nat := pad
    for n in sorted do
      let (_, h) := n.kind.size
      pos := pos.insert n.id (x, y)
      y := y + h + rowGap
      if y > maxY then maxY := y
    maxX := x + colW
    x := x + colW + colGap
  -- Reserve room at the bottom for the clock distribution rail.
  let railY    := maxY + clkRail / 2
  let totalW   := maxX + pad
  let totalH   := maxY + clkRail + pad
  let nodeMap : Std.HashMap String DiagNode :=
    d.nodes.foldl (fun m n => m.insert n.id n) {}
  let defs := "<defs>" ++
    "<marker id='arrow' viewBox='0 0 10 10' refX='9' refY='5' markerWidth='6' markerHeight='6' orient='auto'>" ++
    "<path d='M 0 0 L 10 5 L 0 10 z' fill='#444'/></marker>" ++
    "<marker id='arrow-clk' viewBox='0 0 10 10' refX='9' refY='5' markerWidth='6' markerHeight='6' orient='auto'>" ++
    "<path d='M 0 0 L 10 5 L 0 10 z' fill='#c2185b'/></marker>" ++
    "</defs>"
  let mut svg : String := ""
  -- Pass 1: data + bus edges
  for e in d.edges do
    let (sId, _)    := parsePortRef e.src   -- source side: just the node
    let (dId, dPort) := parsePortRef e.dst
    match e.kind with
    | .clock => pure ()  -- handled in pass 2
    | _      =>
      match nodeMap[sId]?, nodeMap[dId]?, pos[sId]?, pos[dId]? with
      | some sN, some dN, some (sx, sy), some (dx, dy) =>
        let (sxa, sya) := anchorRight sN sx sy
        let (dxa, dya) := anchorLeftPort dN dx dy dPort
        let midX := (sxa + dxa) / 2
        let path := s!"M {sxa} {sya} C {midX} {sya} {midX} {dya} {dxa} {dya}"
        let (stroke, width, label) := match e.kind with
          | .data   => ("#444", "1.6", "")
          | .bus  w => ("#444", "3",   toString w)
          | .clock  => ("#444", "1.6", "")  -- unreachable (filtered above)
        svg := svg ++ s!"<path d='{path}' fill='none' stroke='{stroke}' stroke-width='{width}' marker-end='url(#arrow)'/>"
        if label != "" then
          let lx := midX
          let ly := (sya + dya) / 2 - 4
          svg := svg ++ s!"<text x='{lx}' y='{ly}' text-anchor='middle' font-size='10' fill='#666' font-family='monospace'>{label}</text>"
      | _, _, _, _ => pure ()
  -- Pass 2: clock edges. Use a dedicated rail at `railY`. From the
  -- clock source we drop down to the rail; from each destination we
  -- approach from below (climbs up from rail to the bottom edge of the
  -- target node). The rail itself (horizontal stretch between source
  -- and destination column) is drawn implicitly by the path L
  -- commands.
  for e in d.edges do
    match e.kind with
    | .clock =>
      let (sId, _)     := parsePortRef e.src
      let (dId, _dPort) := parsePortRef e.dst
      match nodeMap[sId]?, nodeMap[dId]?, pos[sId]?, pos[dId]? with
      | some sN, some _dN, some (sx, sy), some (dx, dy) =>
        let (sxa, _) := anchorRight sN sx sy
        -- Source: leave from the bottom-centre of the clk node.
        let (sw, sh) := sN.kind.size
        let srcX := sx + sw / 2
        let srcY := sy + sh
        -- Destination: arrive at the bottom-centre of the target.
        let dN' := nodeMap[dId]!
        let (dw, dh) := dN'.kind.size
        let dstX := dx + dw / 2
        let dstY := dy + dh
        let _ := sxa
        let path := s!"M {srcX} {srcY} L {srcX} {railY} L {dstX} {railY} L {dstX} {dstY}"
        svg := svg ++
          s!"<path d='{path}' fill='none' stroke='#c2185b' style='stroke-dasharray:5,3;' stroke-width='1.4' marker-end='url(#arrow-clk)'/>"
      | _, _, _, _ => pure ()
    | _ => pure ()
  -- Nodes (drawn last so they sit on top of the wires)
  for n in d.nodes do
    match pos[n.id]? with
    | some (nx, ny) => svg := svg ++ renderNode n nx ny
    | none => pure ()
  let outer := s!"<svg xmlns='http://www.w3.org/2000/svg' width='{totalW}' height='{totalH}'>" ++
    defs ++
    s!"<rect width='{totalW}' height='{totalH}' fill='white'/>" ++
    svg ++
    "</svg>"
  emit "image/svg+xml" outer

/-- Render a Mermaid diagram inline. Loads mermaid.js from a CDN on
    the first invocation per page (cached afterwards by the browser);
    each call gets a unique container so multiple diagrams in one
    notebook don't collide. The CDN dependency means this is offline-
    unfriendly — on an air-gapped install, vendor mermaid.min.js
    locally and rewrite the script src.

    Wire format (text/html): a `<div class="mermaid">` with the source
    inside, plus a small bootstrap that lazy-loads mermaid + invokes
    `mermaid.run({nodes: [<this div>]})`. -/
def mermaid (src : String) : IO Unit := do
  -- Cheap unique-ish id derived from the src string; collisions across
  -- cells are harmless (they'd just re-render the same diagram).
  let id := s!"mmd-{(hash src).toUSize.toNat}"
  -- Mermaid parses its source from the element's textContent — and `<`
  -- / `>` carry syntactic meaning (`-->`, `>ALU]`, `[/in/]`), so we
  -- must NOT entity-escape them. Only `&` needs escaping to keep the
  -- HTML well-formed; `<` and `>` are tolerated inside element text.
  let escSrc := src.replace "&" "&amp;"
  let html := String.intercalate "" [
    "<div class='mermaid' id='", id, "'>", escSrc, "</div>",
    "<script>",
    "(function() {",
    "  const id = '", id, "';",
    "  function run() {",
    "    if (window.mermaid && window.mermaid.run) {",
    "      try { window.mermaid.run({ nodes: [document.getElementById(id)] }); } catch(e) { console.warn('mermaid.run failed:', e); }",
    "    }",
    "  }",
    "  if (window.mermaid && window.mermaid.run) {",
    "    run();",
    "  } else if (window.__xleanMermaidLoading) {",
    "    window.__xleanMermaidPending = (window.__xleanMermaidPending || []);",
    "    window.__xleanMermaidPending.push(run);",
    "  } else {",
    "    window.__xleanMermaidLoading = true;",
    "    window.__xleanMermaidPending = [run];",
    "    const s = document.createElement('script');",
    "    s.src = 'https://cdn.jsdelivr.net/npm/mermaid@10.9.0/dist/mermaid.min.js';",
    "    s.onload = function() {",
    "      window.mermaid.initialize({ startOnLoad: false, securityLevel: 'loose' });",
    "      const pending = window.__xleanMermaidPending || [];",
    "      window.__xleanMermaidPending = [];",
    "      for (const fn of pending) fn();",
    "    };",
    "    document.head.appendChild(s);",
    "  }",
    "})();",
    "</script>"
  ]
  emit "text/html" html

/-- Run a `bash -c <cmd>` and emit the result as plain-text cell output:
    stdout first, then stderr (prefixed `stderr:`) if non-empty, then a
    final `[exit N]` line if the command failed. Same shape as the
    Python `%bash`/`!cmd` magic. Used by the `#bash "..."` macro. -/
def bash (cmd : String) : IO Unit := do
  let out ← IO.Process.output { cmd := "bash", args := #["-c", cmd] }
  let mut buf : String := out.stdout
  if !out.stderr.isEmpty then
    if !buf.isEmpty && !buf.endsWith "\n" then buf := buf ++ "\n"
    buf := buf ++ "stderr: " ++ out.stderr
  if out.exitCode != 0 then
    if !buf.isEmpty && !buf.endsWith "\n" then buf := buf ++ "\n"
    buf := buf ++ s!"[exit {out.exitCode}]"
  -- Print to stdout so the existing `withIsolatedStreams` capture path
  -- folds it into the cell's text/plain output. No MIME marker.
  IO.print buf

/-! ### Help registry

`#help_x` lists every notebook command currently registered with
`Display.helpRegister`. The list is a global `IO.Ref` so other modules
(Sparkle helpers, Hesper helpers, user-defined ones) can append their
own entries without touching this file:

```lean
import Display
#eval Display.helpRegister {
  command  := "#bv"
  category := "sparkle"
  brief    := "Show a BitVec literal in binary, hex, and decimal."
  example  := "#bv 0x42#8"
}
```

The categorisation lets us visually group the table; entries are sorted
alphabetically within each category.
-/

structure HelpEntry where
  command  : String   -- e.g. "#findDecl"
  category : String   -- e.g. "search", "display", "waveform", "sparkle"
  brief    : String   -- one-line description
  -- `usage` rather than `example` because the latter is a Lean keyword.
  usage    : String   -- one-line usage snippet
  deriving Inhabited

initialize helpRegistry : IO.Ref (Array HelpEntry) ← IO.mkRef #[]

/-- Add (or replace) a help entry. Idempotent: re-registering the same
    `command` overwrites the previous entry, so reloading the notebook
    cell that registered it doesn't pile up duplicates. -/
def helpRegister (e : HelpEntry) : IO Unit := do
  helpRegistry.modify fun arr =>
    let filtered := arr.filter (·.command != e.command)
    filtered.push e

/-- Render the help table as `text/html`. Pure formatting; the macro
    handles I/O. `filterCmd` (e.g. `"#findDecl"`) restricts to one
    command's row when set; otherwise all entries. -/
def helpTableHtml (entries : Array HelpEntry) (filterCmd : Option String := none) : String := Id.run do
  let kept := match filterCmd with
    | none => entries
    | some c => entries.filter (·.command == c)
  let sorted := kept.qsort fun a b =>
    if a.category != b.category then a.category < b.category else a.command < b.command
  let mut rows : String := ""
  let mut lastCat : String := ""
  for e in sorted do
    if e.category != lastCat then
      rows := rows ++
        "<tr><td colspan='2' style='text-align:left;padding:6px 8px;background:#fafafa;border-top:1px solid #ddd;font-weight:600;color:#666;font-size:11px;text-transform:uppercase;letter-spacing:0.5px'>" ++
        e.category ++ "</td></tr>"
      lastCat := e.category
    let safeBrief := e.brief.replace "<" "&lt;" |>.replace ">" "&gt;"
    let safeExample := e.usage.replace "<" "&lt;" |>.replace ">" "&gt;"
    rows := rows ++
      "<tr>" ++
      "<td style='text-align:left;padding:4px 12px 4px 8px;font-weight:600;color:#1565c0;white-space:nowrap;vertical-align:top'><code>" ++ e.command ++ "</code></td>" ++
      "<td style='text-align:left;padding:4px 8px;font-size:12px;color:#333'>" ++ safeBrief ++
      "<div style='margin-top:2px;color:#888;font-size:11px'>e.g. <code>" ++ safeExample ++ "</code></div></td>" ++
      "</tr>"
  let title := match filterCmd with
    | none => s!"xlean help — {sorted.size} commands"
    | some c => s!"xlean help — <code>{c}</code>"
  -- `display:inline-block` makes the outer div hug its content so the
  -- table sits on the left of the cell rather than stretching across
  -- the full notebook width. `text-align:left` on every cell guards
  -- against parent rules (JupyterLab's `.jp-RenderedHTML` sometimes
  -- centres direct children) that would otherwise center the column.
  pure <|
    "<div style='font-family:monospace;border:1px solid #ddd;background:white;display:inline-block;max-width:100%;overflow:auto;text-align:left'>" ++
    "<div style='padding:6px 8px;background:#f5f5f5;border-bottom:1px solid #ddd;font-size:12px;text-align:left'>" ++ title ++ "</div>" ++
    "<table style='border-collapse:collapse;text-align:left'><tbody>" ++ rows ++ "</tbody></table>" ++
    "</div>"

/-! ### Interactive waveform sessions

A `WaveformSession` is a server-side trace exposed to a JS frontend
through a Jupyter `comm` channel (see `CommBus`). The kernel keeps
the signals as `Nat → Bool` functions — never materializing the full
trace — and answers per-window queries from the JS viewer. Scrolling
or zooming in the viewer triggers a fresh query, so the viewer can
walk through arbitrarily long traces without sending the whole thing
across the wire.

Wire format (JSON):

* JS → Lean (`comm_msg.data`):
    `{op: "query", t0: <Nat>, t1: <Nat>, lod: <Nat>}`
  where `lod = 0` requests every tick; `lod = k` requests one summary
  point per `2^k` ticks (boolean OR over the window).

* Lean → JS (`comm.send`):
    `{op: "result", t0, t1, lod, lanes: [{name, bits: "<base64-packed>"}, …]}`
  Each `bits` is the lane's values over `[t0, t1)` packed 8 per byte
  (LSB = first tick) and base64-encoded.
-/

namespace WaveformSession

/-- Pack a `List Bool` 8 bits per byte (little-endian: index 0 → bit 0
    of byte 0). Returns `(byteCount, ByteArray)`. -/
private def packBits (bits : Array Bool) : ByteArray := Id.run do
  let n := bits.size
  let nBytes := (n + 7) / 8
  let mut buf : ByteArray := ByteArray.empty
  for byteIx in [0:nBytes] do
    let mut b : UInt8 := 0
    for off in [0:8] do
      let i := byteIx * 8 + off
      if i < n && bits[i]! then
        b := b ||| (1 <<< off.toUInt8)
    buf := buf.push b
  buf

/-- Standard base64 alphabet. -/
private def b64alphabet : String :=
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

/-- Base64-encode a ByteArray. -/
private def base64 (bs : ByteArray) : String := Id.run do
  let alpha := b64alphabet.toList.toArray
  let n := bs.size
  let mut out := ""
  let mut i := 0
  while i + 2 < n do
    let b0 := bs.get! i
    let b1 := bs.get! (i+1)
    let b2 := bs.get! (i+2)
    let triple : UInt32 := b0.toUInt32 <<< 16 ||| b1.toUInt32 <<< 8 ||| b2.toUInt32
    out := out.push (alpha[((triple >>> 18) &&& 0x3F).toNat]!)
    out := out.push (alpha[((triple >>> 12) &&& 0x3F).toNat]!)
    out := out.push (alpha[((triple >>>  6) &&& 0x3F).toNat]!)
    out := out.push (alpha[((triple)         &&& 0x3F).toNat]!)
    i := i + 3
  let rem := n - i
  if rem == 1 then
    let b0 := bs.get! i
    let triple : UInt32 := b0.toUInt32 <<< 16
    out := out.push (alpha[((triple >>> 18) &&& 0x3F).toNat]!)
    out := out.push (alpha[((triple >>> 12) &&& 0x3F).toNat]!)
    out := out ++ "=="
  else if rem == 2 then
    let b0 := bs.get! i
    let b1 := bs.get! (i+1)
    let triple : UInt32 := b0.toUInt32 <<< 16 ||| b1.toUInt32 <<< 8
    out := out.push (alpha[((triple >>> 18) &&& 0x3F).toNat]!)
    out := out.push (alpha[((triple >>> 12) &&& 0x3F).toNat]!)
    out := out.push (alpha[((triple >>>  6) &&& 0x3F).toNat]!)
    out := out ++ "="
  out

/-- Sample a single lane over `[t0, t1)` at the requested level of
    detail. `lod = 0` returns one bit per tick; `lod = k` returns one
    summary bit per `2^k` ticks (true if any tick in the window is
    true — captures "where transitions happened" for zoomed-out views). -/
private def sampleLane (sig : Nat → Bool) (t0 t1 lod : Nat) : Array Bool := Id.run do
  let step : Nat := 1 <<< lod
  let mut out : Array Bool := #[]
  let mut t := t0
  while t < t1 do
    if step == 1 then
      out := out.push (sig t)
    else
      let mut acc := false
      for off in [0:step] do
        if t + off < t1 then
          if sig (t + off) then acc := true
      out := out.push acc
    t := t + step
  out

/-- A signal lane: name + sampler. The sampler is `Nat → Bool` so we
    never need to allocate the full trace. -/
structure Lane where
  name   : String
  sample : Nat → Bool

/-- Build the `op:"result"` JSON for a query. Visible for testing. -/
def buildResult (lanes : List Lane) (totalCycles t0 t1 lod : Nat) : Lean.Json :=
  let t1' := min t1 totalCycles
  let laneJsons := lanes.map fun l =>
    let bits := sampleLane l.sample t0 t1' lod
    Lean.Json.mkObj [
      ("name", Lean.Json.str l.name),
      ("bits", Lean.Json.str (base64 (packBits bits)))
    ]
  Lean.Json.mkObj [
    ("op",          Lean.Json.str "result"),
    ("t0",          Lean.Json.num t0),
    ("t1",          Lean.Json.num t1'),
    ("lod",         Lean.Json.num lod),
    ("totalCycles", Lean.Json.num totalCycles),
    ("lanes",       Lean.Json.arr laneJsons.toArray)
  ]

/-- Per-session mutable state. Lanes can be added and removed at
    runtime, so the comm handler reads from this ref each query rather
    than capturing a fixed list. -/
structure State where
  totalCycles : Nat
  lanes       : Array Lane

/-- Live sessions, keyed by the user-chosen `sessionId`. Multiple
    waveform cells can coexist; the JS frontend picks one by name. -/
initialize sessions : IO.Ref (Std.HashMap String (IO.Ref State)) ←
  IO.mkRef {}

/-- Look up (or fail) the per-session state. -/
private def getState (sessionId : String) : IO (Option (IO.Ref State)) := do
  let m ← sessions.get
  pure m[sessionId]?

/-- Register a waveform session. Once this returns, JS frontends that
    open a comm against target `xlean` with `data.session = sessionId`
    will be wired up to receive `query` → `result` round-trips. The
    initial `lanes` are stored in a session-local `IO.Ref` so cells
    can later add or remove lanes; see `addLane` / `removeLane`. -/
def new (sessionId : String) (lanes : List Lane) (totalCycles : Nat) : IO Unit := do
  let stRef ← IO.mkRef ({ totalCycles, lanes := lanes.toArray } : State)
  sessions.modify (·.insert sessionId stRef)
  CommBus.register sessionId fun data => do
    let op := data.getObjValAs? String "op" |>.toOption.getD ""
    let st ← stRef.get
    match op with
    | "list" =>
      let names := st.lanes.toList.map fun l => Lean.Json.str l.name
      pure <| Lean.Json.mkObj [
        ("op",          Lean.Json.str "list"),
        ("totalCycles", Lean.Json.num st.totalCycles),
        ("lanes",       Lean.Json.arr names.toArray)
      ]
    | "query" =>
      let t0  := data.getObjValAs? Nat "t0"  |>.toOption.getD 0
      let t1  := data.getObjValAs? Nat "t1"  |>.toOption.getD st.totalCycles
      let lod := data.getObjValAs? Nat "lod" |>.toOption.getD 0
      -- Optional lane filter: data.lanes = ["hsync", "de"]. When absent
      -- (or empty) we return all lanes — preserves backwards-compat
      -- with frontends that haven't been updated.
      let filterArr : Array String :=
        match data.getObjVal? "lanes" with
        | .ok (Lean.Json.arr a) => a.filterMap fun j =>
            match j with | Lean.Json.str s => some s | _ => none
        | _ => #[]
      let chosen : List Lane :=
        if filterArr.isEmpty then st.lanes.toList
        else st.lanes.toList.filter (fun l => filterArr.contains l.name)
      pure (buildResult chosen st.totalCycles t0 t1 lod)
    | _ =>
      pure <| Lean.Json.mkObj [
        ("op",     Lean.Json.str "error"),
        ("reason", Lean.Json.str s!"unknown op: {op}")
      ]

/-- Add a lane to a live session. Returns `false` if the session id is
    unknown. The frontend has to ask for an updated lane list (the
    viewer sends `op:"list"` periodically and on add-button click) to
    see the new entry. -/
def addLane (sessionId : String) (lane : Lane) : IO Bool := do
  match ← getState sessionId with
  | none => pure false
  | some stRef =>
    stRef.modify fun s =>
      -- Replace by name if it already exists, else append.
      let existing := s.lanes.findIdx? (·.name == lane.name)
      match existing with
      | some i => { s with lanes := s.lanes.set! i lane }
      | none   => { s with lanes := s.lanes.push lane }
    pure true

/-- Remove a lane by name. Returns `true` if a lane was actually
    removed. -/
def removeLane (sessionId name : String) : IO Bool := do
  match ← getState sessionId with
  | none => pure false
  | some stRef =>
    let before ← stRef.get
    let after  := before.lanes.filter (·.name != name)
    if after.size == before.lanes.size then pure false
    else
      stRef.set { before with lanes := after }
      pure true

end WaveformSession

/-! ### VCD file backend

Read a pre-recorded VCD file once into per-signal transition lists,
then serve queries from the same `WaveformSession` API. The bit-flip
density is what bounds memory, not the tick count — a 1 G-tick trace
with ~100 M transitions occupies ~1.5 GB; for true GB-scale traces an
mmap-based backend is the right answer (left as a follow-up).

The parser is intentionally narrow:

* one-bit signals only (`$var wire 1 <id> <name> $end`); multi-bit
  vectors get stitched onto the bus separately if needed;
* `#<time>` time markers, `0<id>` / `1<id>` value changes;
* everything else (`$timescale`, `$dumpvars`, …) is recognised as a
  framing token and otherwise ignored.

Multi-bit and string values silently round-trip as `false` for now.
-/

private structure VCDState where
  /-- Map from VCD identifier (e.g. `!`) to the sorted list of
      `(time, bit)` transitions for that signal. The list is built
      during parsing and converted to a sorted Array at the end. -/
  transitions : Std.HashMap String (Array (Nat × Bool)) := {}
  /-- Map from VCD identifier to the human-readable signal name
      from the matching `$var` declaration. -/
  names : Std.HashMap String String := {}

/-- Parse a VCD source into per-signal transition arrays. -/
private def parseVCD (src : String) : VCDState := Id.run do
  let mut st : VCDState := {}
  let mut t : Nat := 0
  for line in src.splitOn "\n" do
    let s := line.trimAscii.toString
    if s.isEmpty then continue
    if s.startsWith "$var" then
      -- `$var wire 1 ! cnt $end`
      let parts := s.splitOn " " |>.filter (· ≠ "")
      if parts.length ≥ 5 && parts[1]! == "wire" && parts[2]! == "1" then
        let ident := parts[3]!
        let name  := parts[4]!
        st := { st with names := st.names.insert ident name }
    else if s.startsWith "#" then
      -- `#1234`
      match (s.drop 1).toNat? with
      | some n => t := n
      | none   => pure ()
    else if s.length ≥ 2 && (s.front == '0' || s.front == '1') then
      -- `0!` / `1!` — Lean's `String.drop` returns a String.Slice in
      -- recent stdlib versions, so coerce back via `.toString`.
      let bit   := s.front == '1'
      let ident := (s.drop 1).toString
      if st.names.contains ident then
        let prev := st.transitions.getD ident #[]
        st := { st with transitions := st.transitions.insert ident (prev.push (t, bit)) }
    else
      pure ()
  st

/-- Binary search for the largest index `i` with `arr[i].1 ≤ t`,
    returning the bit at that index, or `false` if `t` precedes
    every transition. -/
private partial def sampleAt (arr : Array (Nat × Bool)) (t : Nat) : Bool :=
  let rec go (lo hi : Nat) : Bool :=
    if lo + 1 ≥ hi then
      if hi == 0 then false else (arr[lo]!).2
    else
      let mid := (lo + hi) / 2
      if (arr[mid]!).1 ≤ t then go mid hi else go lo mid
  if arr.isEmpty then false else go 0 arr.size

/-- Build `Lane`s from a parsed VCD. The lane name is the human-
    readable name from the `$var` declaration; the sampler closes over
    the per-signal transition array and binary-searches on each call. -/
def WaveformSession.fromVCDState (st : VCDState) : List Lane := Id.run do
  let mut out : List Lane := []
  for (ident, name) in st.names.toList do
    let arr := st.transitions.getD ident #[]
    out := { name, sample := fun t => sampleAt arr t } :: out
  out

/-- HTML+JS bundle that drives an interactive waveform viewer.

    The viewer:
    * opens its own WebSocket against `/api/kernels/<id>/channels`
      (kernel id discovered via `/api/kernels` REST), so it doesn't
      need any JupyterLab-extension hooks;
    * sends `comm_open` against target `xlean` with
      `data.session = sessionId`, then `comm_msg` queries to fetch the
      bits for the current viewport;
    * renders to a `<canvas>`, supports horizontal scroll + scroll-wheel
      zoom, picks a level-of-detail so the displayed bit count never
      exceeds the canvas pixel width;
    * caches recently-fetched windows so casual scrubbing doesn't
      thrash the kernel.

    All of the JS is inlined here to keep the cell self-contained. -/
def waveformJSHtml (sessionId : String) (laneNames : List String)
    (totalCycles : Nat) : String :=
  let nameLits := laneNames.map (fun n => "\"" ++ n ++ "\"")
  let namesJs := "[" ++ String.intercalate "," nameLits ++ "]"
  let total := toString totalCycles
  let rootId := "xlean-wave-" ++ sessionId
  String.intercalate "\n" [
    "<div id='" ++ rootId ++ "' class='xlean-wave' data-session='" ++ sessionId ++ "'",
    "     style='font-family:monospace;border:1px solid #ddd;padding:6px;background:white;width:100%;max-width:900px'>",
    "  <div style='display:flex;gap:8px;align-items:center;font-size:12px;color:#333;padding-bottom:4px;flex-wrap:wrap'>",
    "    <button class='xw-zin'  title='zoom in'      style='padding:2px 8px;cursor:pointer'>+</button>",
    "    <button class='xw-zout' title='zoom out'     style='padding:2px 8px;cursor:pointer'>−</button>",
    "    <button class='xw-fit'  title='fit all'      style='padding:2px 8px;cursor:pointer'>Fit</button>",
    "    <span style='position:relative'>",
    "      <button class='xw-add' title='add lane' style='padding:2px 8px;cursor:pointer'>+ lane</button>",
    "      <div class='xw-add-menu' style='display:none;position:absolute;top:100%;left:0;background:white;border:1px solid #ccc;box-shadow:0 2px 8px rgba(0,0,0,.15);z-index:10;max-height:200px;overflow:auto;min-width:120px'></div>",
    "    </span>",
    "    <span style='color:#999;font-size:11px;margin-left:4px'>shift+drag = box-zoom · drag = pan · wheel = zoom</span>",
    "    <span class='xlean-status' style='color:#888;margin-left:auto'></span>",
    "  </div>",
    "  <div class='xw-canvas-wrap' style='position:relative'>",
    "    <canvas style='width:100%;display:block;cursor:grab;user-select:none' tabindex='0'></canvas>",
    "    <div class='xw-lane-overlay' style='position:absolute;top:0;left:0;width:80px;pointer-events:none'></div>",
    "  </div>",
    "  <div style='display:flex;justify-content:space-between;font-size:11px;color:#666;padding-top:4px'>",
    "    <span><strong>session:</strong> <code>" ++ sessionId ++ "</code></span>",
    "    <span><strong>cycles:</strong> " ++ total ++ "</span>",
    "  </div>",
    "</div>",
    "<script>",
    "(function() {",
    "  const sessionId   = " ++ "\"" ++ sessionId ++ "\"" ++ ";",
    "  const totalCycles = " ++ total ++ ";",
    "  const initialLaneNames = " ++ namesJs ++ ";",
    "  const root        = document.getElementById(" ++ "\"" ++ rootId ++ "\"" ++ ");",
    "  const status      = root.querySelector('.xlean-status');",
    "  const canvas      = root.querySelector('canvas');",
    "  const ctx2d       = canvas.getContext('2d');",
    "  const laneOverlay = root.querySelector('.xw-lane-overlay');",
    "  const addBtn      = root.querySelector('.xw-add');",
    "  const addMenu     = root.querySelector('.xw-add-menu');",
    "",
    "  // --- View state ------------------------------------------------------",
    "  // Two viewport copies: `target*` is where we're heading, `cur*` is",
    "  // what's actually on screen. The animation loop lerps cur → target",
    "  // every frame so wheel/zoom motions feel continuous instead of",
    "  // step-changing per event.",
    "  let targetT0   = 0,            curT0   = 0;",
    "  let targetSpan = totalCycles,  curSpan = totalCycles;",
    "  let cache    = new Map();      // key -> { lanes:[{name,bits:Uint8Array}] }",
    "  let pending  = new Map();",
    "  // `lastDraw` keeps the most recent successfully-rendered window so",
    "  // the canvas never flashes blank: while the kernel is computing the",
    "  // new LOD/range we re-stretch lastDraw to fill the current viewport.",
    "  let lastDraw = null;           // { lod, qT0, qT1, lanes }",
    "  // Lane state: `available` is everything the kernel knows about,",
    "  // `visible` is what's actually rendered. Add/remove buttons mutate",
    "  // `visible`; the kernel can mutate `available` between cells via",
    "  // Display.WaveformSession.addLane / removeLane and we refresh on",
    "  // each `+ lane` click.",
    "  let availableLanes = initialLaneNames.slice();",
    "  let visibleLanes   = initialLaneNames.slice();",
    "",
    "  function setStatus(s) { status.textContent = s; }",
    "",
    "  // --- Kernel connection ----------------------------------------------",
    "  let ws        = null;",
    "  let mySession = 'xlean-wave-' + Math.random().toString(16).slice(2);",
    "  let commId    = null;",
    "",
    "  function header(msgType) {",
    "    return {",
    "      msg_id: (crypto.randomUUID ? crypto.randomUUID() : (Date.now()+Math.random()).toString(36)),",
    "      session: mySession, username: 'xlean-wave', date: new Date().toISOString(),",
    "      msg_type: msgType, version: '5.3'",
    "    };",
    "  }",
    "  function send(msg) { ws.send(JSON.stringify(msg)); }",
    "",
    "  async function connect() {",
    "    setStatus('locating kernel…');",
    "    const r = await fetch('/api/kernels');",
    "    const ks = await r.json();",
    "    if (!ks.length) { setStatus('no kernel'); return; }",
    "    const kid = ks[0].id;",
    "    const proto = location.protocol === 'https:' ? 'wss:' : 'ws:';",
    "    const url = `${proto}//${location.host}/api/kernels/${kid}/channels?session_id=${mySession}`;",
    "    ws = new WebSocket(url);",
    "    ws.onopen = () => {",
    "      setStatus('opening comm…');",
    "      commId = (crypto.randomUUID ? crypto.randomUUID().replace(/-/g,'') : Math.random().toString(16).slice(2));",
    "      send({",
    "        header: header('comm_open'), parent_header: {}, metadata: {},",
    "        content: { comm_id: commId, target_name: 'xlean', data: { session: sessionId } },",
    "        channel: 'shell', buffers: []",
    "      });",
    "      // Refresh the list of available lanes after a brief delay (so",
    "      // the comm_open has actually been processed server-side).",
    "      setTimeout(refreshLaneList, 100);",
    "      kickAnimation();",
    "    };",
    "    ws.onmessage = (evt) => {",
    "      const msg = JSON.parse(evt.data);",
    "      if (msg.msg_type === 'comm_msg' && msg.content.comm_id === commId) {",
    "        const data = msg.content.data;",
    "        if (data && data.op === 'result') {",
    "          // Cache key carries the lane set so we don't reuse a result",
    "          // from a different selection.",
    "          const laneKey = (data.lanes || []).map(l => l.name).join(',');",
    "          const key = data.lod + '|' + data.t0 + '|' + data.t1 + '|' + laneKey;",
    "          const decoded = data.lanes.map(l => ({ name: l.name, bits: b64decode(l.bits) }));",
    "          cache.set(key, { lanes: decoded });",
    "          pending.delete(key);",
    "          kickAnimation();",
    "        } else if (data && data.op === 'list') {",
    "          availableLanes = data.lanes.slice();",
    "          // First time we see the canonical list, seed visibleLanes",
    "          // (preserves whatever subset the user already toggled on).",
    "          if (visibleLanes.length === 0) visibleLanes = availableLanes.slice();",
    "          // Drop visibles that no longer exist.",
    "          visibleLanes = visibleLanes.filter(n => availableLanes.includes(n));",
    "          renderLaneOverlay();",
    "          kickAnimation();",
    "        }",
    "      }",
    "    };",
    "    ws.onclose = () => setStatus('disconnected');",
    "  }",
    "",
    "  function refreshLaneList() {",
    "    if (!ws || ws.readyState !== 1 || !commId) return;",
    "    send({",
    "      header: header('comm_msg'), parent_header: {}, metadata: {},",
    "      content: { comm_id: commId, data: { op: 'list' } },",
    "      channel: 'shell', buffers: []",
    "    });",
    "  }",
    "",
    "  function b64decode(s) {",
    "    const bin = atob(s);",
    "    const out = new Uint8Array(bin.length);",
    "    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);",
    "    return out;",
    "  }",
    "",
    "  function bitAt(packed, i) { return (packed[i >> 3] >> (i & 7)) & 1; }",
    "",
    "  function requestWindow(lod, t0, t1, lanes) {",
    "    const laneKey = lanes.join(',');",
    "    const key = lod + '|' + t0 + '|' + t1 + '|' + laneKey;",
    "    if (cache.has(key) || pending.has(key)) return;",
    "    if (!ws || ws.readyState !== 1 || !commId) return;",
    "    pending.set(key, true);",
    "    send({",
    "      header: header('comm_msg'), parent_header: {}, metadata: {},",
    "      content: { comm_id: commId, data: { op: 'query', t0, t1, lod, lanes } },",
    "      channel: 'shell', buffers: []",
    "    });",
    "  }",
    "",
    "  // --- Layout ----------------------------------------------------------",
    "  const labelW = 80, laneH = 28, padTop = 4;",
    "  function plotW() { return canvas.clientWidth - labelW; }",
    "  function chooseLod(span, plotPx) {",
    "    let lod = 0;",
    "    while ((span >>> lod) > plotPx) lod++;",
    "    return lod;",
    "  }",
    "  function clampViewport(t0, span) {",
    "    span = Math.max(8, Math.min(totalCycles, span));",
    "    t0 = Math.max(0, Math.min(totalCycles - span, t0));",
    "    return { t0, span };",
    "  }",
    "",
    "  // --- Drawing ---------------------------------------------------------",
    "  // Render lanes from a `frame` (lod/qT0/qT1/lanes) onto the current",
    "  // viewport. `frame` may be the freshly-fetched window for the current",
    "  // viewport, or `lastDraw` (an older one whose pixel positions are",
    "  // computed by the same map). Either way the lines fill the canvas.",
    "  function drawFrame(frame, vT0, vT1) {",
    "    const w = canvas.clientWidth, h = canvas.clientHeight;",
    "    const span = Math.max(1, vT1 - vT0);",
    "    const step = 1 << frame.lod;",
    "    const pixPerTick = (w - labelW) / span;",
    "    ctx2d.strokeStyle = '#1976d2'; ctx2d.lineWidth = 1.5;",
    "    frame.lanes.forEach((lane, i) => {",
    "      const yTop = padTop + i * laneH + 2;",
    "      const yBot = padTop + i * laneH + laneH - 6;",
    "      ctx2d.beginPath();",
    "      let prevY = yBot, started = false;",
    "      // Walk by sample (frame domain) so we always hit the actual data.",
    "      const startIx = Math.max(0, Math.floor((vT0 - frame.qT0) / step));",
    "      const endIx   = Math.min((frame.qT1 - frame.qT0) >>> frame.lod, Math.ceil((vT1 - frame.qT0) / step) + 1);",
    "      for (let ix = startIx; ix < endIx; ix++) {",
    "        const t = frame.qT0 + ix * step;",
    "        const v = bitAt(lane.bits, ix);",
    "        const x = labelW + (t - vT0) * pixPerTick;",
    "        const y = v ? yTop : yBot;",
    "        if (!started) { ctx2d.moveTo(x, y); started = true; }",
    "        else if (y !== prevY) { ctx2d.lineTo(x, prevY); ctx2d.lineTo(x, y); }",
    "        else { ctx2d.lineTo(x, y); }",
    "        ctx2d.lineTo(x + step * pixPerTick, y);",
    "        prevY = y;",
    "      }",
    "      ctx2d.stroke();",
    "    });",
    "  }",
    "",
    "  function drawChrome() {",
    "    ctx2d.fillStyle = '#333'; ctx2d.font = '11px monospace';",
    "    visibleLanes.forEach((name, i) => {",
    "      // Leave space on the right for the [×] overlay button.",
    "      ctx2d.fillText(name, 4, padTop + i * laneH + laneH / 2 + 4);",
    "    });",
    "    ctx2d.strokeStyle = '#ddd'; ctx2d.lineWidth = 1;",
    "    ctx2d.beginPath();",
    "    ctx2d.moveTo(labelW, 0); ctx2d.lineTo(labelW, canvas.clientHeight);",
    "    ctx2d.stroke();",
    "  }",
    "",
    "  function renderLaneOverlay() {",
    "    laneOverlay.innerHTML = '';",
    "    laneOverlay.style.height = (visibleLanes.length * laneH + 24) + 'px';",
    "    visibleLanes.forEach((name, i) => {",
    "      const btn = document.createElement('button');",
    "      btn.textContent = '×';",
    "      btn.title = 'hide ' + name;",
    "      btn.style.cssText = 'position:absolute;right:4px;top:' + (padTop + i * laneH + 4) + 'px;width:16px;height:16px;line-height:14px;padding:0;cursor:pointer;pointer-events:auto;background:white;border:1px solid #ccc;font-size:11px;color:#666';",
    "      btn.addEventListener('click', () => {",
    "        visibleLanes = visibleLanes.filter(n => n !== name);",
    "        renderLaneOverlay();",
    "        kickAnimation();",
    "      });",
    "      laneOverlay.appendChild(btn);",
    "    });",
    "  }",
    "",
    "  // The selection rect (shift+drag) is a transient overlay, so we keep",
    "  // it as state and draw it after the lanes each frame.",
    "  let selRect = null;  // {x0, x1} in canvas-css pixels",
    "  // Hover state: x of the cursor in canvas-css pixels, or null when",
    "  // the cursor is off the canvas. Used to draw a vertical caret +",
    "  // textual readout of the values at that tick.",
    "  let hoverX = null;",
    "",
    "  function drawFrameAll() {",
    "    // Make sure CSS height tracks the visible-lane count so a hidden",
    "    // lane shrinks the canvas instead of leaving a gap.",
    "    const desiredH = visibleLanes.length * laneH + 24;",
    "    if (canvas.style.height !== desiredH + 'px') canvas.style.height = desiredH + 'px';",
    "    const dpr = window.devicePixelRatio || 1;",
    "    const cssW = canvas.clientWidth, cssH = canvas.clientHeight;",
    "    if (canvas.width !== cssW * dpr || canvas.height !== cssH * dpr) {",
    "      canvas.width = cssW * dpr; canvas.height = cssH * dpr;",
    "      ctx2d.setTransform(dpr, 0, 0, dpr, 0, 0);",
    "    }",
    "    ctx2d.clearRect(0, 0, cssW, cssH);",
    "    ctx2d.fillStyle = 'white'; ctx2d.fillRect(0, 0, cssW, cssH);",
    "    drawChrome();",
    "    // Resolve the ideal frame for this viewport.",
    "    const vT0 = curT0;",
    "    const vT1 = Math.min(totalCycles, curT0 + curSpan);",
    "    const lod = chooseLod(vT1 - vT0, cssW - labelW);",
    "    const step = 1 << lod;",
    "    const qT0 = (Math.max(0, Math.floor(vT0)) >>> lod) << lod;",
    "    const qT1 = Math.min(totalCycles, ((Math.ceil(vT1) + step - 1) >>> lod) << lod);",
    "    requestWindow(lod, qT0, qT1, visibleLanes);",
    "    const laneKey = visibleLanes.join(',');",
    "    const key = lod + '|' + qT0 + '|' + qT1 + '|' + laneKey;",
    "    const cached = cache.get(key);",
    "    if (cached) {",
    "      lastDraw = { lod, qT0, qT1, lanes: cached.lanes };",
    "      drawFrame(lastDraw, vT0, vT1);",
    "      setStatus('view t=[' + Math.round(vT0) + ',' + Math.round(vT1) + ') lod=' + lod);",
    "    } else if (lastDraw) {",
    "      drawFrame(lastDraw, vT0, vT1);",
    "      setStatus('loading t=[' + qT0 + ',' + qT1 + ') lod=' + lod + '… (showing previous)');",
    "    } else {",
    "      setStatus('loading t=[' + qT0 + ',' + qT1 + ') lod=' + lod + '…');",
    "    }",
    "    if (selRect) {",
    "      ctx2d.fillStyle = 'rgba(25,118,210,0.15)';",
    "      ctx2d.fillRect(Math.min(selRect.x0, selRect.x1), 0, Math.abs(selRect.x1 - selRect.x0), cssH);",
    "      ctx2d.strokeStyle = '#1976d2'; ctx2d.lineWidth = 1;",
    "      ctx2d.strokeRect(Math.min(selRect.x0, selRect.x1) + 0.5, 0.5, Math.abs(selRect.x1 - selRect.x0), cssH - 1);",
    "    }",
    "    // Hover caret + readout. Resolves the tick under the cursor and,",
    "    // for each visible lane, looks up its bit in lastDraw (the most",
    "    // recently fetched window). When a fresh fetch hasn't landed yet",
    "    // we silently skip the readout rather than show stale values.",
    "    if (hoverX !== null && hoverX >= labelW && lastDraw) {",
    "      const xFrac = (hoverX - labelW) / Math.max(1, cssW - labelW);",
    "      const tHover = Math.round(vT0 + xFrac * (vT1 - vT0));",
    "      // Vertical caret",
    "      ctx2d.strokeStyle = 'rgba(244,67,54,0.7)'; ctx2d.lineWidth = 1;",
    "      ctx2d.beginPath();",
    "      ctx2d.moveTo(hoverX + 0.5, 0); ctx2d.lineTo(hoverX + 0.5, cssH);",
    "      ctx2d.stroke();",
    "      // Readout pill",
    "      const sampleStep = 1 << lastDraw.lod;",
    "      const ix = (tHover - lastDraw.qT0) >>> lastDraw.lod;",
    "      const valid = ix >= 0 && ix < ((lastDraw.qT1 - lastDraw.qT0) >>> lastDraw.lod);",
    "      // Build the readout string.",
    "      let readout = 't=' + tHover;",
    "      if (valid) {",
    "        for (const lane of lastDraw.lanes) {",
    "          if (!visibleLanes.includes(lane.name)) continue;",
    "          readout += '  ' + lane.name + '=' + bitAt(lane.bits, ix);",
    "        }",
    "      }",
    "      ctx2d.font = '11px monospace';",
    "      const textW = ctx2d.measureText(readout).width;",
    "      const padX = 6, padY = 4;",
    "      let pillX = hoverX + 8;",
    "      const pillW = textW + 2 * padX, pillH = 18;",
    "      // Flip to the left of the caret if the pill would clip the right edge.",
    "      if (pillX + pillW > cssW - 4) pillX = hoverX - 8 - pillW;",
    "      ctx2d.fillStyle = 'rgba(33,33,33,0.85)';",
    "      ctx2d.fillRect(pillX, 4, pillW, pillH);",
    "      ctx2d.fillStyle = '#fff';",
    "      ctx2d.fillText(readout, pillX + padX, 4 + pillH / 2 + 4);",
    "    }",
    "  }",
    "",
    "  // --- Animation loop --------------------------------------------------",
    "  let rafPending = false;",
    "  function kickAnimation() {",
    "    if (rafPending) return;",
    "    rafPending = true;",
    "    requestAnimationFrame(animFrame);",
    "  }",
    "  function animFrame() {",
    "    rafPending = false;",
    "    // Lerp cur → target with a fixed coefficient. Visually, motion",
    "    // settles in ~10 frames (≈ 170 ms at 60 Hz).",
    "    const r = 0.25;",
    "    const dT0   = targetT0   - curT0;",
    "    const dSpan = targetSpan - curSpan;",
    "    const moving = Math.abs(dT0) > 0.5 || Math.abs(dSpan) > 0.5;",
    "    if (moving) {",
    "      curT0   += dT0   * r;",
    "      curSpan += dSpan * r;",
    "    } else {",
    "      curT0 = targetT0; curSpan = targetSpan;",
    "    }",
    "    drawFrameAll();",
    "    if (moving) kickAnimation();",
    "  }",
    "",
    "  function setTarget(t0, span) {",
    "    const c = clampViewport(t0, span);",
    "    targetT0 = c.t0; targetSpan = c.span;",
    "    kickAnimation();",
    "  }",
    "  function setTargetInstant(t0, span) {",
    "    const c = clampViewport(t0, span);",
    "    targetT0 = c.t0; targetSpan = c.span;",
    "    curT0 = targetT0; curSpan = targetSpan;",
    "    kickAnimation();",
    "  }",
    "",
    "  // --- Interaction -----------------------------------------------------",
    "  // Toolbar",
    "  root.querySelector('.xw-zin').addEventListener('click', () => {",
    "    setTarget(targetT0 + targetSpan * 0.25, targetSpan * 0.5);",
    "  });",
    "  root.querySelector('.xw-zout').addEventListener('click', () => {",
    "    const newSpan = Math.min(totalCycles, targetSpan * 2);",
    "    setTarget(targetT0 - (newSpan - targetSpan) / 2, newSpan);",
    "  });",
    "  root.querySelector('.xw-fit').addEventListener('click', () => {",
    "    setTarget(0, totalCycles);",
    "  });",
    "  // \"+ lane\" button: re-pull the canonical list (so cells that called",
    "  // Display.WaveformSession.addLane after the viewer was created get",
    "  // picked up), then show a small dropdown of the hidden lanes.",
    "  addBtn.addEventListener('click', (e) => {",
    "    e.stopPropagation();",
    "    refreshLaneList();",
    "    // Brief delay to let the list reply land.",
    "    setTimeout(() => {",
    "      addMenu.innerHTML = '';",
    "      const hidden = availableLanes.filter(n => !visibleLanes.includes(n));",
    "      if (hidden.length === 0) {",
    "        const empty = document.createElement('div');",
    "        empty.textContent = '(all lanes shown)';",
    "        empty.style.cssText = 'padding:6px 10px;color:#999;font-size:11px';",
    "        addMenu.appendChild(empty);",
    "      } else {",
    "        hidden.forEach(name => {",
    "          const item = document.createElement('div');",
    "          item.textContent = name;",
    "          item.style.cssText = 'padding:4px 10px;cursor:pointer;font-size:12px';",
    "          item.addEventListener('mouseenter', () => item.style.background = '#f0f7ff');",
    "          item.addEventListener('mouseleave', () => item.style.background = '');",
    "          item.addEventListener('click', () => {",
    "            visibleLanes.push(name);",
    "            renderLaneOverlay();",
    "            addMenu.style.display = 'none';",
    "            kickAnimation();",
    "          });",
    "          addMenu.appendChild(item);",
    "        });",
    "      }",
    "      addMenu.style.display = 'block';",
    "    }, 120);",
    "  });",
    "  // Close the menu on any outside click.",
    "  document.addEventListener('click', (e) => {",
    "    if (!addMenu.contains(e.target) && e.target !== addBtn) {",
    "      addMenu.style.display = 'none';",
    "    }",
    "  });",
    "",
    "  // Pan (drag) and box-fit (shift+drag).",
    "  let drag = null;  // { x0, t0AtStart, mode }",
    "  function mouseToTick(e, useTarget) {",
    "    const rect = canvas.getBoundingClientRect();",
    "    const xFrac = Math.max(0, Math.min(1, (e.clientX - rect.left - labelW) / Math.max(1, plotW())));",
    "    const t0   = useTarget ? targetT0   : curT0;",
    "    const span = useTarget ? targetSpan : curSpan;",
    "    return t0 + xFrac * span;",
    "  }",
    "  function canvasX(e) {",
    "    const rect = canvas.getBoundingClientRect();",
    "    return Math.max(labelW, Math.min(canvas.clientWidth, e.clientX - rect.left));",
    "  }",
    "  canvas.addEventListener('mousedown', (e) => {",
    "    if (e.shiftKey) {",
    "      drag = { mode: 'box', x0: canvasX(e), x1: canvasX(e) };",
    "      selRect = { x0: drag.x0, x1: drag.x0 };",
    "      kickAnimation();",
    "    } else {",
    "      drag = { mode: 'pan', x: e.clientX, t0: targetT0 };",
    "      canvas.style.cursor = 'grabbing';",
    "    }",
    "    e.preventDefault();",
    "  });",
    "  window.addEventListener('mousemove', (e) => {",
    "    if (!drag) return;",
    "    if (drag.mode === 'pan') {",
    "      const dx = e.clientX - drag.x;",
    "      const ticksPerPixel = targetSpan / Math.max(1, plotW());",
    "      setTargetInstant(drag.t0 - dx * ticksPerPixel, targetSpan);",
    "    } else if (drag.mode === 'box') {",
    "      drag.x1 = canvasX(e);",
    "      selRect = { x0: drag.x0, x1: drag.x1 };",
    "      kickAnimation();",
    "    }",
    "  });",
    "  // Track hover separately so the readout updates even when no drag",
    "  // is active. Throttle to one rAF tick so we don't spam redraws.",
    "  canvas.addEventListener('mousemove', (e) => {",
    "    const rect = canvas.getBoundingClientRect();",
    "    hoverX = e.clientX - rect.left;",
    "    kickAnimation();",
    "  });",
    "  canvas.addEventListener('mouseleave', () => {",
    "    hoverX = null;",
    "    kickAnimation();",
    "  });",
    "  window.addEventListener('mouseup', () => {",
    "    if (!drag) return;",
    "    if (drag.mode === 'box' && Math.abs(drag.x1 - drag.x0) > 4) {",
    "      const lo = Math.min(drag.x0, drag.x1), hi = Math.max(drag.x0, drag.x1);",
    "      const ticksPerPixel = targetSpan / Math.max(1, plotW());",
    "      const newT0   = targetT0 + (lo - labelW) * ticksPerPixel;",
    "      const newSpan = (hi - lo) * ticksPerPixel;",
    "      setTarget(newT0, newSpan);",
    "    }",
    "    selRect = null;",
    "    drag = null;",
    "    canvas.style.cursor = 'grab';",
    "    kickAnimation();",
    "  });",
    "",
    "  canvas.addEventListener('wheel', (e) => {",
    "    e.preventDefault();",
    "    const factor = Math.exp(e.deltaY * 0.0015);",
    "    const newSpan = Math.max(8, Math.min(totalCycles, targetSpan * factor));",
    "    const tCursor = mouseToTick(e, true);",
    "    const rect = canvas.getBoundingClientRect();",
    "    const xFrac = Math.max(0, Math.min(1, (e.clientX - rect.left - labelW) / Math.max(1, plotW())));",
    "    setTarget(tCursor - xFrac * newSpan, newSpan);",
    "  }, { passive: false });",
    "  canvas.addEventListener('dblclick', () => setTarget(0, totalCycles));",
    "  new ResizeObserver(() => kickAnimation()).observe(canvas);",
    "",
    "  renderLaneOverlay();",
    "  connect();",
    "})();",
    "</script>"
  ]

/-- Convenience entry point that registers the session AND emits the
    HTML/JS frontend bundle as a `text/html` MIME payload. The JS
    opens a comm with target `xlean` and `data.session = sessionId`,
    then drives the view from `query` ↔ `result` round-trips.

    `lanes` are `Nat → Bool` samplers — we never realize the full
    trace, so this scales to multi-million-cycle simulations. -/
def waveformInteractive (sessionId : String) (lanes : List WaveformSession.Lane)
    (totalCycles : Nat) : IO Unit := do
  WaveformSession.new sessionId lanes totalCycles
  emit "text/html" (waveformJSHtml sessionId (lanes.map (·.name)) totalCycles)

/-! #### `.wdb` — block-compressed waveform database

A first-principles binary format. Spec (all multi-byte little-endian):

```
Header (24 B): "WDB1", version u32, totalTicks u64, blockCount u64
SignalTable    : u32 sigCount, then sigCount × { u16 name_len, name, u16 width }
BlockIndex     : blockCount × { u64 startTick, u64 fileOffset, u32 compSize,
                                u32 transitions }
Block payload  : zstd-compressed body of
                 transitions × { varint sigIdx, varint deltaTick, u8 value }
```

Why this rather than VCD or FST:

* Per-block + per-signal compression with `zstd -3` typically beats FST's
  LZ4 by 30–50% on hardware traces (sparse signals + repetitive runs).
* Random access at block granularity: `query t0..t1` reads only the index
  and the intersecting blocks, never the whole trace.
* No external library: we shell out to the system `zstd`, which is
  packaged everywhere we run.
* Apache-2.0 friendly. (FST is GPLv2.)
-/

namespace Wdb

/-- Append a varint-encoded `Nat` (LEB128) to a `ByteArray`. -/
def putVarint (buf : ByteArray) (n : Nat) : ByteArray := Id.run do
  let mut v := n
  let mut out := buf
  while true do
    let b : UInt8 := UInt8.ofNat (v &&& 0x7f)
    let v' := v >>> 7
    if v' == 0 then
      out := out.push b
      break
    else
      out := out.push (b ||| 0x80)
      v := v'
  out

/-- Read a varint starting at `i`; return `(value, nextIndex)`. -/
partial def getVarint (bs : ByteArray) (i : Nat) : Nat × Nat := Id.run do
  let mut v : Nat := 0
  let mut shift : Nat := 0
  let mut j := i
  while j < bs.size do
    let b := bs.get! j
    v := v ||| ((b.toNat &&& 0x7f) <<< shift)
    j := j + 1
    if b &&& 0x80 == 0 then return (v, j)
    shift := shift + 7
  pure (v, j)

/-- u16 → 2 bytes LE. -/
def putU16 (buf : ByteArray) (n : Nat) : ByteArray :=
  buf.push (UInt8.ofNat (n &&& 0xff))
     |>.push (UInt8.ofNat ((n >>> 8) &&& 0xff))

/-- u32 → 4 bytes LE. -/
def putU32 (buf : ByteArray) (n : Nat) : ByteArray :=
  buf.push (UInt8.ofNat (n &&& 0xff))
     |>.push (UInt8.ofNat ((n >>>  8) &&& 0xff))
     |>.push (UInt8.ofNat ((n >>> 16) &&& 0xff))
     |>.push (UInt8.ofNat ((n >>> 24) &&& 0xff))

/-- u64 → 8 bytes LE. -/
def putU64 (buf : ByteArray) (n : Nat) : ByteArray := Id.run do
  let mut out := buf
  let mut v := n
  for _ in [0:8] do
    out := out.push (UInt8.ofNat (v &&& 0xff))
    v := v >>> 8
  out

/-- Read u32 LE. -/
private def getU32 (bs : ByteArray) (i : Nat) : UInt32 :=
  let b0 := (bs.get! i).toUInt32
  let b1 := (bs.get! (i+1)).toUInt32 <<<  8
  let b2 := (bs.get! (i+2)).toUInt32 <<< 16
  let b3 := (bs.get! (i+3)).toUInt32 <<< 24
  b0 ||| b1 ||| b2 ||| b3

/-- Read u64 LE as Nat. -/
def getU64 (bs : ByteArray) (i : Nat) : Nat := Id.run do
  let mut v : Nat := 0
  for k in [0:8] do
    v := v ||| ((bs.get! (i + k)).toNat <<< (8 * k))
  v

/-- Read u16 LE. -/
def getU16 (bs : ByteArray) (i : Nat) : Nat :=
  (bs.get! i).toNat ||| ((bs.get! (i+1)).toNat <<< 8)

/-- One transition record before block packing. -/
structure Transition where
  sigIdx : Nat
  tick   : Nat
  value  : Bool
  deriving Inhabited

/-- Run `zstd` in subprocess to compress the body and write to `dst`.
    Uses level 3 (default) — good balance for sparse waveform data. -/
def zstdCompress (body : ByteArray) (dstPath : String) : IO Unit := do
  -- Write the raw body to a tmp, then `zstd -3 -f --rm tmp -o dst`.
  let tmp := dstPath ++ ".raw"
  IO.FS.writeBinFile tmp body
  let r ← IO.Process.output {
    cmd := "zstd", args := #["-3", "-f", "-q", "--rm", tmp, "-o", dstPath]
  }
  if r.exitCode != 0 then
    throw <| IO.userError s!"zstd compress failed: {r.stderr}"

/-- Run `zstd -d` to decompress a slice of bytes. The standalone slice
    must be a valid zstd frame; we write it to a temp file and read the
    decompressed result. -/
def zstdDecompressBytes (compressed : ByteArray) : IO ByteArray := do
  let inTmp ← IO.Process.output { cmd := "mktemp", args := #["-p", "/tmp", "wdb.in.XXXXXX"] }
  let outTmp ← IO.Process.output { cmd := "mktemp", args := #["-p", "/tmp", "wdb.out.XXXXXX"] }
  let inPath := inTmp.stdout.trimRight
  let outPath := outTmp.stdout.trimRight
  IO.FS.writeBinFile inPath compressed
  let r ← IO.Process.output {
    cmd := "zstd", args := #["-d", "-f", "-q", inPath, "-o", outPath]
  }
  if r.exitCode != 0 then
    discard <| (IO.FS.removeFile inPath).toBaseIO
    discard <| (IO.FS.removeFile outPath).toBaseIO
    throw <| IO.userError s!"zstd decompress failed: {r.stderr}"
  let bs ← IO.FS.readBinFile outPath
  discard <| (IO.FS.removeFile inPath).toBaseIO
  discard <| (IO.FS.removeFile outPath).toBaseIO
  pure bs

/-- Block target — number of transitions per block. Picked so that the
    typical block compresses to a few KB at zstd-3 on sparse traces. -/
def blockTargetTransitions : Nat := 65536

/-- Walk one signal sampler `Nat → Bool` and record every transition in
    `[0, totalTicks)`. The first sample (tick 0) is always recorded as
    a transition so each signal has a known starting value. -/
def collectTransitions (sigIdx : Nat) (sample : Nat → Bool)
    (totalTicks : Nat) : Array Transition := Id.run do
  let mut out : Array Transition := #[]
  if totalTicks == 0 then return out
  let mut prev := sample 0
  out := out.push { sigIdx, tick := 0, value := prev }
  for t in [1:totalTicks] do
    let v := sample t
    if v != prev then
      out := out.push { sigIdx, tick := t, value := v }
      prev := v
  out

end Wdb

/-- Write a `.wdb` file from a list of `WaveformSession.Lane` samplers.
    Walks each signal once, batches transitions into blocks, zstd-
    compresses each block, and writes the on-disk layout described in
    the file header comment.

    Cost: O(totalTicks × #lanes) wall time (one Bool call per tick per
    lane). Output size on a typical sparse trace: 50–200 bytes/lane on
    long stretches of unchanging value, plus a few bytes per actual
    transition. -/
def writeWdb (filename : String) (lanes : List WaveformSession.Lane)
    (totalTicks : Nat) : IO Unit := do
  -- 1. Collect & merge transitions across all signals, sorted by tick.
  let mut all : Array Wdb.Transition := #[]
  let mut i : Nat := 0
  for l in lanes do
    all := all ++ (Wdb.collectTransitions i l.sample totalTicks)
    i := i + 1
  let lanesArr := lanes.toArray
  let sorted := all.qsort fun a b =>
    if a.tick != b.tick then a.tick < b.tick else a.sigIdx < b.sigIdx
  -- 2. Slice into blocks.
  let mut blocks : Array (Array Wdb.Transition) := #[]
  let mut cur : Array Wdb.Transition := #[]
  for tr in sorted do
    cur := cur.push tr
    if cur.size ≥ Wdb.blockTargetTransitions then
      blocks := blocks.push cur
      cur := #[]
  if !cur.isEmpty then blocks := blocks.push cur
  -- 3. Compress each block; remember the compressed bytes + transition
  --    count + start tick. We assemble the full file in memory; for
  --    multi-GB outputs we'd stream, but at zstd ratios that's a
  --    distant problem.
  let scratchDir : String := filename ++ ".d"
  IO.FS.createDirAll scratchDir
  let mut compBlocks : Array (Nat × Nat × ByteArray) := #[]   -- (startTick, transitions, compressed)
  let mut idx := 0
  for blk in blocks do
    let startTick := if blk.isEmpty then 0 else blk[0]!.tick
    -- Encode block body with delta-tick relative to startTick.
    let mut body : ByteArray := ByteArray.empty
    for tr in blk do
      body := Wdb.putVarint body tr.sigIdx
      body := Wdb.putVarint body (tr.tick - startTick)
      body := body.push (if tr.value then 1 else 0)
    let outPath := s!"{scratchDir}/blk{idx}.zst"
    Wdb.zstdCompress body outPath
    let comp ← IO.FS.readBinFile outPath
    discard <| (IO.FS.removeFile outPath).toBaseIO
    compBlocks := compBlocks.push (startTick, blk.size, comp)
    idx := idx + 1
  discard <| (IO.FS.removeDir scratchDir).toBaseIO
  -- 4. Build the file: header → signal table → block index → blocks.
  let blockCount := compBlocks.size
  let mut buf : ByteArray := ByteArray.empty
  -- Header
  buf := buf.push 'W'.toNat.toUInt8
       |>.push 'D'.toNat.toUInt8
       |>.push 'B'.toNat.toUInt8
       |>.push '1'.toNat.toUInt8
  buf := Wdb.putU32 buf 1                     -- version
  buf := Wdb.putU64 buf totalTicks
  buf := Wdb.putU64 buf blockCount
  -- SignalTable
  buf := Wdb.putU32 buf lanesArr.size
  for l in lanesArr do
    let nameBytes := l.name.toUTF8
    buf := Wdb.putU16 buf nameBytes.size
    for k in [0:nameBytes.size] do buf := buf.push (nameBytes.get! k)
    buf := Wdb.putU16 buf 1                   -- width = 1 (v1 single-bit)
  -- We need to compute fileOffset for each block; the index lives
  -- before the blocks, and is fixed-size (24 bytes per entry), so we
  -- can compute the "after-index" offset.
  let indexSize := blockCount * 24
  let blocksStart := buf.size + indexSize
  -- BlockIndex
  let mut runningOffset := blocksStart
  for (startTick, transitions, comp) in compBlocks do
    buf := Wdb.putU64 buf startTick
    buf := Wdb.putU64 buf runningOffset
    buf := Wdb.putU32 buf comp.size
    buf := Wdb.putU32 buf transitions
    runningOffset := runningOffset + comp.size
  -- Block payloads
  for (_, _, comp) in compBlocks do
    for k in [0:comp.size] do buf := buf.push (comp.get! k)
  IO.FS.writeBinFile filename buf

/-- Read header + signal table + block index from a `.wdb` file.
    Returns enough to seek into specific blocks on demand. -/
private structure WdbHandle where
  path        : String
  totalTicks  : Nat
  signalNames : Array String
  /-- (startTick, fileOffset, compSize, transitions) -/
  blockIndex  : Array (Nat × Nat × Nat × Nat)

private def readWdbHeader (path : String) : IO WdbHandle := do
  let bs ← IO.FS.readBinFile path
  if bs.size < 24 then throw <| IO.userError s!"file too small to be wdb: {path}"
  if bs.get! 0 != 'W'.toNat.toUInt8 ∨ bs.get! 1 != 'D'.toNat.toUInt8
   ∨ bs.get! 2 != 'B'.toNat.toUInt8 ∨ bs.get! 3 != '1'.toNat.toUInt8 then
    throw <| IO.userError s!"not a wdb1 file: {path}"
  let totalTicks := Wdb.getU64 bs 8
  let blockCount := Wdb.getU64 bs 16
  -- SignalTable starts at byte 24.
  let mut p := 24
  let sigCount := (Wdb.getU32 bs p).toNat
  p := p + 4
  let mut names : Array String := #[]
  for _ in [0:sigCount] do
    let nameLen := Wdb.getU16 bs p
    p := p + 2
    let nameBytes := bs.extract p (p + nameLen)
    p := p + nameLen
    let _w := Wdb.getU16 bs p   -- width (unused in v1)
    p := p + 2
    names := names.push (String.fromUTF8! nameBytes)
  -- BlockIndex
  let mut idx : Array (Nat × Nat × Nat × Nat) := #[]
  for _ in [0:blockCount] do
    let startTick := Wdb.getU64 bs p; p := p + 8
    let fileOff   := Wdb.getU64 bs p; p := p + 8
    let compSize  := (Wdb.getU32 bs p).toNat; p := p + 4
    let trans     := (Wdb.getU32 bs p).toNat; p := p + 4
    idx := idx.push (startTick, fileOff, compSize, trans)
  pure { path, totalTicks, signalNames := names, blockIndex := idx }

/-- Decompress one block (by its index entry) and return the array of
    `(sigIdx, tick, value)` transitions in original order. -/
private def readWdbBlock (h : WdbHandle) (block : Nat × Nat × Nat × Nat) :
    IO (Array Wdb.Transition) := do
  let (startTick, fileOff, compSize, _trans) := block
  let allBs ← IO.FS.readBinFile h.path
  let comp := allBs.extract fileOff (fileOff + compSize)
  let body ← Wdb.zstdDecompressBytes comp
  let mut out : Array Wdb.Transition := #[]
  let mut p := 0
  while p < body.size do
    let (sigIdx, p1) := Wdb.getVarint body p
    let (deltaTick, p2) := Wdb.getVarint body p1
    let v := body.get! p2 != 0
    out := out.push { sigIdx, tick := startTick + deltaTick, value := v }
    p := p2 + 1
  pure out

/-- Materialise the full per-signal transition list from a `.wdb`. We
    walk every block once (in order) so the result is sorted by tick.
    Memory: O(total transitions) — fine for traces up to a few hundred
    M transitions; for true streaming we'd lazily decompress per
    query. -/
private def readWdbAll (h : WdbHandle) :
    IO (Std.HashMap Nat (Array (Nat × Bool))) := do
  let mut perSig : Std.HashMap Nat (Array (Nat × Bool)) := {}
  for entry in h.blockIndex do
    let trs ← readWdbBlock h entry
    for tr in trs do
      let cur := perSig.getD tr.sigIdx #[]
      perSig := perSig.insert tr.sigIdx (cur.push (tr.tick, tr.value))
  pure perSig

/-- Open a `.wdb` and register an interactive waveform session backed by
    it. Same JS frontend as `Display.waveformInteractive`. -/
def waveformFromWdb (sessionId : String) (path : String) : IO Unit := do
  let h ← readWdbHeader path
  let perSig ← readWdbAll h
  let lanes : List WaveformSession.Lane := h.signalNames.toList.mapIdx fun i name =>
    let arr := perSig.getD i #[]
    { name, sample := fun t => sampleAt arr t }
  WaveformSession.new sessionId lanes h.totalTicks
  emit "text/html" (waveformJSHtml sessionId h.signalNames.toList h.totalTicks)

/-- Convenience: read a VCD file from disk, parse it, and register an
    interactive waveform session backed by it. The resulting session
    serves the same JS frontend as `Display.waveformInteractive`. -/
def waveformFromVCDFile (sessionId : String) (path : String) : IO Unit := do
  let src ← IO.FS.readFile path
  let st  := parseVCD src
  -- Total cycles = max time across all transitions.
  let total := st.transitions.toList.foldl
    (fun acc (_, arr) => arr.foldl (fun a (tm, _) => max a tm) acc) 0
  let lanes := WaveformSession.fromVCDState st
  WaveformSession.new sessionId lanes (total + 1)
  emit "text/html" (waveformJSHtml sessionId (lanes.map (·.name)) (total + 1))

/-! ### Declaration search helpers

`#findDecl "Signal.reg"`         — first 10 matches, case-insensitive substring
`#findDecl "Signal" "reg"`       — AND search across multiple keywords
`#findDecl "Signal.reg" 10 20`   — page: skip 10, take 20
`#listNs Sparkle.Core.Signal`    — declarations whose name starts with that prefix
`#sig Signal.register`           — single declaration's type signature

The walks the active `Lean.Environment` and filters in O(env-size); current
Lean stdlibs have ~50–200k constants which scans in <100 ms. Internal /
auto-generated names (`._aux`, `._proof_`, `._@.`) are filtered by default
because they swamp results.
-/

namespace Search

/-- Substring containment by walking the haystack's chars. We materialize
    char arrays once and slide a window — fine for the ~50–200k name list
    we're scanning at search time. -/
def containsStr (haystack needle : String) : Bool :=
  if needle.isEmpty then true
  else
    let h := haystack.toList.toArray
    let n := needle.toList.toArray
    if n.size > h.size then false
    else Id.run do
      let limit := h.size - n.size + 1
      for i in [0:limit] do
        let mut ok := true
        for j in [0:n.size] do
          if h[i + j]! != n[j]! then
            ok := false
            break
        if ok then return true
      return false

/-- True for names that should not appear in user-facing search output. -/
def isHidden (n : Lean.Name) : Bool :=
  n.isInternal
  || containsStr n.toString "._@."
  || containsStr n.toString "._aux"
  || containsStr n.toString "._proof_"
  || containsStr n.toString "._eq_"
  || containsStr n.toString "._unsafe_"
  || containsStr n.toString "._cstage"
  || containsStr n.toString "._sunfold"
  || containsStr n.toString "._mutual"
  || containsStr n.toString ".match_"
  || containsStr n.toString ".pre_"
  || containsStr n.toString ".brec_"

/-- Lower-case a String. -/
def lower (s : String) : String := s.toLower

/-- Returns true iff `name` (lowercased) contains every keyword (lowercased). -/
def matchesAll (lname : String) (keywords : Array String) : Bool := Id.run do
  for k in keywords do
    unless containsStr lname k.toLower do return false
  return true

/-- Rank a match — smaller is better. Used for ordering results. -/
def rank (name lname : String) (keywords : Array String) : Nat := Id.run do
  -- Highest priority: exact match on first keyword
  if keywords.size > 0 ∧ name == keywords[0]! then return 0
  -- Next: name ends with first keyword (suffix-match for `Foo.bar`-style queries)
  if keywords.size > 0 ∧ lname.endsWith ("." ++ keywords[0]!.toLower) then return 1
  -- Next: prefix match
  if keywords.size > 0 ∧ lname.startsWith keywords[0]!.toLower then return 2
  -- Otherwise: number of dotted segments (shorter, higher-level names rank better)
  return 100 + (name.splitOn ".").length

/-- Walk the env, return matching `(name, type)` pairs (sorted by rank then
    alphabetically). Internal declarations are filtered by default. -/
def find (env : Lean.Environment) (keywords : Array String)
    (includeInternal : Bool := false) : Array (Lean.Name × Lean.Expr) := Id.run do
  let mut hits : Array (Nat × String × Lean.Name × Lean.Expr) := #[]
  for (n, ci) in env.constants.toList do
    unless includeInternal ∨ !isHidden n do continue
    let s := n.toString
    let ls := s.toLower
    unless matchesAll ls keywords do continue
    hits := hits.push (rank s ls keywords, ls, n, ci.type)
  -- Sort by (rank, lowercase-name)
  let sorted := hits.qsort (fun (r1, l1, _, _) (r2, l2, _, _) =>
    if r1 != r2 then r1 < r2 else l1 < l2)
  sorted.map (fun (_, _, n, t) => (n, t))

end Search

/-- Pretty-print one declaration's type signature. -/
def ppSigOf (n : Lean.Name) (e : Lean.Expr) : Lean.MetaM String := do
  let pp ← Lean.PrettyPrinter.ppExpr e
  pure (toString pp)

/-- Build the HTML table for a page of search results. Pure formatting; the
    elab callers handle pretty-printing of types via the meta context. -/
def declTableHtml (rows : Array (String × String)) (skip take total : Nat)
    (queryDescr : String) : String := Id.run do
  let mut body : String := ""
  for (name, typ) in rows do
    let safeType := typ.replace "<" "&lt;" |>.replace ">" "&gt;"
    body := body ++
      "<tr><td style='text-align:left;padding:2px 8px;font-weight:600;color:#1565c0;white-space:nowrap;vertical-align:top'>" ++
      name ++
      "</td><td style='text-align:left;padding:2px 8px;color:#333;font-size:11px'><code>" ++
      safeType ++ "</code></td></tr>"
  let lastShown := skip + rows.size
  let summary :=
    if total == 0 then "no matches"
    else s!"showing {skip+1}–{lastShown} of {total}" ++
         (if lastShown < total then " (use page args to see more)" else "")
  pure <|
    "<div style='font-family:monospace;border:1px solid #ddd;background:white;display:inline-block;max-width:100%;overflow:auto;text-align:left'>" ++
    "<div style='padding:6px 8px;background:#f5f5f5;border-bottom:1px solid #ddd;font-size:12px;text-align:left'>" ++
    queryDescr ++ " — <em>" ++ summary ++ "</em></div>" ++
    "<table style='border-collapse:collapse;font-size:12px;text-align:left'><tbody>" ++
    body ++
    "</tbody></table></div>"

end Display

open Lean Lean.Elab Lean.Elab.Command Lean.Meta in
/-- `#findDecl "kw1" "kw2"? ... skipN? takeN?` — substring search across the
    current environment. Returns up to 10 results by default, ranked by how
    closely the name matches the first keyword. -/
elab "#findDecl " kws:(str)+ skipTk:(num)? takeTk:(num)? : command => do
  let keywords : Array String := kws.map (·.getString)
  let skipN := skipTk.map (·.getNat) |>.getD 0
  let takeN := takeTk.map (·.getNat) |>.getD 10
  let env ← getEnv
  let hits := Display.Search.find env keywords (includeInternal := false)
  let page := hits.extract skipN (skipN + takeN)
  -- Pretty-print types in the term-elab monad.
  let rows ← liftTermElabM do
    let mut acc : Array (String × String) := #[]
    for (n, t) in page do
      let pp ← Display.ppSigOf n t
      acc := acc.push (n.toString, pp)
    pure acc
  let descr := "find " ++ String.intercalate " ∧ "
    (keywords.toList.map (fun k => "\"" ++ k ++ "\""))
  let html := Display.declTableHtml rows skipN takeN hits.size descr
  liftCoreM <| Display.emit "text/html" html

open Lean Lean.Elab Lean.Elab.Command Lean.Meta in
/-- `#listNs Sparkle.Core.Signal skipN? takeN?` — list declarations whose
    fully-qualified name starts with the given namespace prefix. -/
elab "#listNs " ns:ident skipTk:(num)? takeTk:(num)? : command => do
  let prefixStr := ns.getId.toString
  let skipN := skipTk.map (·.getNat) |>.getD 0
  let takeN := takeTk.map (·.getNat) |>.getD 10
  let env ← getEnv
  let needle := (prefixStr ++ ".").toLower
  let mut hits : Array (Name × Expr) := #[]
  for (n, ci) in env.constants.toList do
    if Display.Search.isHidden n then continue
    let s := n.toString.toLower
    if s.startsWith needle then
      hits := hits.push (n, ci.type)
  let sorted := hits.qsort (fun (a, _) (b, _) => a.toString < b.toString)
  let page := sorted.extract skipN (skipN + takeN)
  let rows ← liftTermElabM do
    let mut acc : Array (String × String) := #[]
    for (n, t) in page do
      let pp ← Display.ppSigOf n t
      acc := acc.push (n.toString, pp)
    pure acc
  let html := Display.declTableHtml rows skipN takeN sorted.size s!"namespace {prefixStr}"
  liftCoreM <| Display.emit "text/html" html

open Lean Lean.Elab Lean.Elab.Command Lean.Meta in
/-- `#sig SomeFunction` — short type signature for a single declaration. -/
elab "#sig " id:ident : command => do
  let env ← getEnv
  let n := id.getId
  match env.find? n with
  | none =>
    Display.emit "text/html" (s!"<span style='color:#c62828;font-family:monospace'>no such declaration: <code>{n}</code></span>")
      |> liftCoreM
  | some ci =>
    let typeStr ← liftTermElabM do Display.ppSigOf n ci.type
    let safe := typeStr.replace "<" "&lt;" |>.replace ">" "&gt;"
    let html := s!"<div style='font-family:monospace;font-size:12px'><strong style='color:#1565c0'>{n}</strong> : <code>{safe}</code></div>"
    Display.emit "text/html" html |> liftCoreM

/-! ## Sugar commands

`#html` / `#latex` / `#md` / `#svg` / `#json` expand to
`#eval Display.<fn> "..."`. The REPL auto-imports `Display` (see
`REPL/Frontend.lean`) so these names resolve in user cells. -/

macro "#html "  s:str : command => `(#eval Display.html $s)
macro "#latex " s:str : command => `(#eval Display.latex $s)
macro "#md "    s:str : command => `(#eval Display.markdown $s)
macro "#svg "   s:str : command => `(#eval Display.svg $s)
macro "#json "  s:str : command => `(#eval Display.json $s)

/-- `#bash "ls /tmp"` — run a one-liner under `bash -c` and dump
    stdout/stderr into the cell output. The Python equivalent is the
    `!ls` shell escape; Lean has no built-in shell escape syntax so
    this macro fills the gap. -/
macro "#bash "  s:str : command => `(#eval Display.bash $s)

/-- `#savefig "fig.svg"` — save the most recent `Display.svg` /
    `Display.html` / `Display.markdown` / `Display.json` /
    `Display.latex` payload to a file. The MIME type is inferred
    from the extension. Useful for grabbing inline figures into
    LaTeX/Markdown manuscripts without re-running the kernel. -/
macro "#savefig " s:str : command => `(#eval Display.savefig $s)

/-- `#mermaid "graph TD; A-->B"` — render a Mermaid diagram inline.
    On first call per page mermaid.js is fetched from a CDN; subsequent
    diagrams reuse the cached library. See `Display.mermaid` for details. -/
macro "#mermaid " s:str : command => `(#eval Display.mermaid $s)

/-! ### Built-in help entries

These register on `import Display`. New entries from other modules
(`SparkleHelp`, future `HesperHelp`, …) call `Display.helpRegister` at
their own initialise time, so users only need to `import` the helper
module they care about and `#help_x` will pick up the new commands. -/

/-- Built-in help entries. Registered lazily on the first `#help_x`
    invocation (we cannot `initialize` them in this same module — Lean's
    `[init]` rule forbids consuming `helpRegistry` from a `do`-block in
    the module that defines it). -/
private def builtinHelp : Array Display.HelpEntry := #[
  { command := "#html",     category := "display",
    brief := "Inline HTML output (rendered as text/html).",
    usage := "#html \"<b>hello</b>\"" },
  { command := "#latex",    category := "display",
    brief := "Inline LaTeX block (rendered as text/latex).",
    usage := "#latex \"\\\\frac{1}{n}\"" },
  { command := "#md",       category := "display",
    brief := "Inline Markdown.",
    usage := "#md \"## section\"" },
  { command := "#svg",      category := "display",
    brief := "Inline SVG output.",
    usage := "#svg \"<svg width='40' height='40'><circle cx='20' cy='20' r='18' fill='red'/></svg>\"" },
  { command := "#json",     category := "display",
    brief := "Inline application/json output.",
    usage := "#json \"{\\\"a\\\":1}\"" },
  { command := "#mermaid",  category := "display",
    brief := "Inline Mermaid diagram (loads mermaid.js from CDN on first use). For hardware block diagrams use shapes: [(R)] register, >ALU] logic, [/in/] port, -.-> clock, ==>|n| bus.",
    usage := "#mermaid \"flowchart LR\\n  IN --> R1[(R1)] --> ALU>ALU] --> R2[(R2)] --> OUT\\n  CLK -.-> R1 & R2\"" },
  { command := "#blockDiagram", category := "display",
    brief := "Structured HW block diagram (port/reg/mux/cloud/box/andG/orG/notG/adder/const/clk + data/clock/bus edges). Trapezoid MUX, real cloud, gate symbols — shapes Mermaid can't do. Layout uses col/row fields on each node.",
    usage := "#eval Display.blockDiagram { nodes := [...], edges := [...] }" },
  { command := "#bash",     category := "shell",
    brief := "Run a one-liner under `bash -c` and dump its output to the cell.",
    usage := "#bash \"ls /tmp\"" },
  { command := "#savefig",  category := "display",
    brief := "Save the most recent rich-display payload to a file. MIME type inferred from extension (.svg, .html, .md, .json, .tex).",
    usage := "#savefig \"figure.svg\"" },
  { command := "Display.bv", category := "display",
    brief := "Pretty-print a BitVec n as a bin/hex/dec table.",
    usage := "#eval Display.bv (0x42#8 : BitVec 8)" },
  { command := "#findDecl", category := "search",
    brief := "Substring-search the env for declarations. AND mode + paging.",
    usage := "#findDecl \"Signal\" \"register\" 0 10" },
  { command := "#listNs",   category := "search",
    brief := "List declarations under a namespace prefix.",
    usage := "#listNs Sparkle.Core.Signal" },
  { command := "#sig",      category := "search",
    brief := "Show one declaration's type signature.",
    usage := "#sig Nat.succ" },
  { command := "#help_x",   category := "meta",
    brief := "Show this help table. Optional argument restricts to one command.",
    usage := "#help_x \"#bash\"  -- describe one command" },
  { command := "Display.waveform",         category := "waveform",
    brief := "Render a List Nat as an inline SVG waveform (single lane).",
    usage := "#eval Display.waveform \"cnt[7:0]\" samples 8 28 80" },
  { command := "Display.boolWave",         category := "waveform",
    brief := "Render N Bool lanes stacked on a single shared time-axis SVG.",
    usage := "#eval Display.boolWave [(\"SCL\", scls), (\"SDA\", sdas)] 5 28" },
  { command := "Display.waveformInteractive", category := "waveform",
    brief := "Interactive viewer: lazy Nat→Bool samplers + comm-based query, scrolls/zooms over multi-million ticks without flooding the cell.",
    usage := "#eval Display.waveformInteractive \"sess\" lanes 100000" },
  { command := "Display.waveformFromVCDFile", category := "waveform",
    brief := "Same interactive viewer, backed by a VCD file. Loads transitions into memory (best for traces under a few hundred MB).",
    usage := "#eval Display.waveformFromVCDFile \"sess\" \"trace.vcd\"" },
  { command := "Display.writeWdb",         category := "waveform",
    brief := "Write a compact, zstd-compressed `.wdb` (xeus-lean's own per-block trace format). 50–100× smaller than VCD on sparse signals.",
    usage := "#eval Display.writeWdb \"trace.wdb\" lanes totalTicks" },
  { command := "Display.waveformFromWdb",  category := "waveform",
    brief := "Open a `.wdb` and serve it through the same interactive viewer; only the relevant blocks are decompressed for each query.",
    usage := "#eval Display.waveformFromWdb \"sess\" \"trace.wdb\"" },
  { command := "Display.writeGz",          category := "waveform",
    brief := "Write a string to a gzip-compressed file. Good fit for VCD: GTKWave reads `.vcd.gz` natively, ~10× smaller than plain VCD.",
    usage := "#eval Display.writeGz \"trace.vcd.gz\" vcdString" }
]

private def ensureBuiltinHelp : IO Unit := do
  let entries ← Display.helpRegistry.get
  if entries.any (·.command == "#help_x") then return
  for e in builtinHelp do Display.helpRegister e

open Lean Lean.Elab Lean.Elab.Command in
/-- `#help_x` (no arg) lists every registered notebook command;
    `#help_x "#findDecl"` filters to one entry. -/
elab "#help_x" filter:(str)? : command => do
  liftCoreM (ensureBuiltinHelp : IO _)
  let entries ← liftCoreM (Display.helpRegistry.get : IO _)
  let html := Display.helpTableHtml entries (filter.map (·.getString))
  liftCoreM <| Display.emit "text/html" html
