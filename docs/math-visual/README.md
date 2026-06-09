# Visual Math Tutorials for xeus-lean

Visual, browser-runnable math tutorials in the spirit of Tristan
Needham's *Visual Complex Analysis*: every key concept is shown as a
diagram first, then explored numerically with live cells, and finally
stated as a formal Lean / Mathlib theorem.

These are kept separate from:
- `../tutorial/md/` — the Lean-as-a-language introduction (Ch00–Ch15)
- `../tutorials/` — operational docs (Docker setup, troubleshooting)

so a reader who comes here is opting into "I want the math, I want the
pictures, I want the formal statement next to the picture."

## Chapters

Priority is roughly LLM-frontier impact × ease of visualisation.

### Must-have

| Chapter folder | Topic | Mathlib bundle |
|---|---|---|
| [`complex-analysis/`](complex-analysis/) | Conformal maps, Möbius, Riemann sphere, contour integrals | `Mathlib.Analysis` |
| [`manifolds/`](manifolds/) | Tangent spaces, differential forms, curvature | `Mathlib.Geometry` + `Mathlib.LinearAlgebra` |
| [`category/`](category/) | Functors, natural transformations, monoidal categories | `Mathlib.CategoryTheory.*` |

### Strongly recommended

| Chapter folder | Topic | Mathlib bundle |
|---|---|---|
| [`optimal-transport/`](optimal-transport/) | Wasserstein distance, Kantorovich duality | `Mathlib.MeasureTheory` |
| [`information-geometry/`](information-geometry/) | Fisher metric, statistical manifolds | `Mathlib.MeasureTheory` + `Mathlib.Geometry` |
| [`lie/`](lie/) | Lie groups & representation theory | `Mathlib.RepresentationTheory` |

### Nice-to-have

| Chapter folder | Topic | Mathlib bundle |
|---|---|---|
| [`pde/`](pde/) | PDE basics, Sobolev spaces | `Mathlib.Analysis` |
| [`representation/`](representation/) | Representation theory deeper | `Mathlib.RepresentationTheory` |

## Format

Each chapter is a markdown file with fenced ` ```lean ` blocks.
`xlean-convert` turns it into a runnable `.ipynb`.  Cells alternate:

1. **Picture** — a `Display.svg "..."` or `#mermaid` cell that shows
   the geometric idea.
2. **Numerical exploration** — `#eval`s on small examples.
3. **Formal statement** — a Lean theorem or `example` using Mathlib.

So the same notebook is readable as prose, runnable as a kernel
session, and grep-able for Lean facts.

## Loading Mathlib

The browser kernel ships without Mathlib by default to keep cold boot
small.  Each chapter starts with a `%load mathlib` cell that pulls in
the needed namespace chunks on demand.

Chrome caps **WASM linear memory** at 4 GB per tab even under
`-sMEMORY64=1`.  That's the number that trips
`RuntimeError: memory access out of bounds` once you combine
`%load mathlib` + `import Mathlib.Tactic` + heavy tactics.  Two
practical work-arounds:

- **Prefer narrow imports.**  `import Mathlib.Tactic.Ring` instead
  of `import Mathlib.Tactic`, `import Mathlib.Topology.ContinuousMap.
  Basic` instead of `import Mathlib`.  `import Mathlib.Tactic` alone
  adds ~1.8 GB to the wasm cap; a single subsequent `by ring` then
  has only ~1.4 GB of headroom before OOM.
- **If you do load the umbrella, do it once per session and don't
  exercise heavy tactics.**  Restart the kernel between exploration
  blocks if the wasm number nears 3 GB.

To watch where memory is going, run `%memory` in a cell:

```text
=== xeus-lean memory snapshot ===
WASM linear memory: 2.79 GB / 4.00 GB (69%, Lean runtime — OOM hits at ~4 GB)
  ↳ Lean (excl. MEMFS): 2.79 GB
MEMFS /lib/lean:    6.77 GB  (46844 files, standalone Uint8Array — costs V8 heap, not WASM)
JS heap (V8):       n/a (performance.memory needs COOP/COEP)
IndexedDB:          6.80 GB / 16.80 GB (40%, disk-only)
```

Two things worth knowing about that output:

- **MEMFS does not count against the wasm cap.**  emscripten 3.x
  stores file contents in standalone `Uint8Array`s in the V8 heap,
  so a 6 GB /lib/lean is fine — what kills the tab is the wasm
  number on the top line.
- **`%memory` reports JS heap as `n/a`** because the site doesn't
  set COOP/COEP headers, which Chrome now requires to expose
  `performance.memory`.  The OS task manager's "Memory footprint"
  column is the practical fallback for the V8 heap.

Sandwich any expensive cell between two `%memory` cells to see how
much wasm the elaboration cost — the delta on the first line is the
actual budget you have left.

## How a new chapter ships

This subtree is wired into CI by `scripts/ci-build-docs.sh` and
`.github/workflows/docs.yml`.  When you push an md file under
`docs/math-visual/<series>/Ch*.md`:

1. The docs-deploy workflow pulls the prebuilt kernel image from
   ghcr (no Lean / emscripten rebuild — md edits don't invalidate
   the kernel).
2. `xlean-convert --to ipynb` emits `notebooks/Ch*.ipynb`, which
   JupyterLite ships alongside the kernel.
3. `xlean-convert --site` builds `_output/math-visual/<series>/`
   (static HTML, prev/next nav, sidebar) with an "Open in
   JupyterLite" button on every chapter page.
4. The `math-visual-tests` job runs `xlean-convert --eval` on every
   `Ch*.md` so chapters where a `#eval` cell broke since the last
   build fail the workflow.

So editing a chapter, pushing, and seeing the live deploy takes
minutes — not a full kernel rebuild.

## Local preview

```bash
# render every chapter to ipynb under notebooks/
for f in docs/math-visual/*/Ch*.md ; do
  lake exec xlean-convert --to ipynb "$f" \
    -o "notebooks/$(basename "$f" .md).ipynb"
done

# render the static site for one series
lake exec xlean-convert --site docs/math-visual/complex-analysis \
  -o _site/complex-analysis --title "Visual Complex Analysis"
xdg-open _site/complex-analysis/index.html
```
