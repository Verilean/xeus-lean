# Visual Real Analysis

A picture-first walk through the analysis of real-valued functions,
written for `xeus-lean`'s browser kernel.

The companion track to [`../complex-analysis/`](../complex-analysis/),
following the same three-step rhythm:

1. **Picture** — an SVG / Mermaid diagram of the geometric idea.
2. **Numerical exploration** — `Float`-based `#eval` cells you can
   poke at and watch the answers update.
3. **Formal statement** — a Mathlib theorem (`Real`, `Continuous`,
   `HasDerivAt`, `MeasureTheory`) standing next to the picture, so
   the proof and the intuition aren't in separate books.

## Chapters

| Ch | Topic | What you'll see |
|----|-------|-----------------|
| [00](Ch00_NumericsAndMathlib.md) | Two worlds: `Float` vs `Real` | Why `#eval` doesn't compute `Real.exp` and what to do about it |
| [01](Ch01_Continuity.md)         | Continuity, ε–δ, limits         | Animating the ε–δ box and tying it to `Continuous` in Mathlib |
| [02](Ch02_Derivatives.md)        | Derivatives, tangent lines, MVT | Tangent at a point as a limit, mean-value theorem geometrically |
| [03](Ch03_Integrals.md)          | Riemann sums, FTC               | Convergence of left/right/midpoint sums, fundamental theorem |

Future chapters (Ch04+) will cover sequences and series, uniform
convergence, and metric spaces — opened in subsequent PRs.

## Reading order

If you've already worked through `complex-analysis/Ch00`, the
numerics setup here will feel familiar — the same `Float` story
applies to `Real` since `Complex = Real × Real`.  Otherwise start at
[Ch00](Ch00_NumericsAndMathlib.md).
