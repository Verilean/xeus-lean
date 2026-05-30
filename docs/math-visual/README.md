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
