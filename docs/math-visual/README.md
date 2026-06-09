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

On Chrome the renderer's JS heap is capped at ~3.7 GB, so a session
that combines `%load mathlib` + `import Mathlib.Tactic` + heavy
tactics (`ring`, `simp` with the full Mathlib lemma set) can OOM
once.  Two practical work-arounds:

- **Restart the kernel after `%load mathlib`.**  The olean cache
  lives in IndexedDB, so the next `import` reads from disk rather
  than re-staging the Blob in heap.  The chapter then runs in a
  much smaller footprint.
- **Prefer narrow imports.**  `import Mathlib.Tactic.Ring` over
  `import Mathlib.Tactic`, `import Mathlib.Topology.ContinuousMap.
  Basic` over `import Mathlib`.

To see where memory is going, run `%memory` in a cell:

```text
=== xeus-lean memory snapshot ===
WASM linear memory: 1.83 GB  (Lean runtime + MEMFS combined)
JS heap (V8):       412.7 MB / 3.62 GB (11%)
MEMFS /lib/lean:    1.42 GB  (8132 files, sits inside WASM linear memory above)
IndexedDB:          7.3 GB / 9.8 GB (74%, disk-only)
```

Sandwich any expensive cell between two `%memory` cells to see how
much heap the elaboration cost.

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
