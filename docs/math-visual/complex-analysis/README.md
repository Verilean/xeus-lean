# Complex Analysis — Visual Track

Ten chapters covering complex analysis in the spirit of Tristan
Needham's *Visual Complex Analysis*: a picture per idea, then a
numerical cell, then a formal Lean statement, then exercises.

Read them in order; each builds on the previous.

| Chapter | Topic |
|---|---|
| [Ch01 Conformal Maps](Ch01_Conformal.md) | Multiplication = rotation × scaling; conformality; first Möbius transformation |
| [Ch02 Möbius Transformations](Ch02_Mobius.md) | Four-block decomposition (translate, invert, scale); cross-ratio invariant |
| [Ch03 Riemann Sphere](Ch03_RiemannSphere.md) | Stereographic projection; one-point compactification; inversion as sphere rotation |
| [Ch04 Contour Integration](Ch04_ContourIntegration.md) | ∮ dz/z = 2πi; Cauchy's theorem; residues glimpsed; deformation invariance |
| [Ch05 Residues](Ch05_Residues.md) | Real integrals via imaginary paths; residue theorem applications |
| [Ch06 Argument Principle](Ch06_ArgumentPrinciple.md) | Winding-number root counting; Rouché's theorem; FTA via Liouville |
| [Ch07 Rigidity](Ch07_Rigidity.md) | Holomorphic ⟹ smooth + analytic; Liouville; identity theorem; maximum modulus |
| [Ch08 Riemann Mapping](Ch08_RiemannMapping.md) | Every simply-connected proper subset of ℂ ≅ disk; Schwarz lemma |
| [Ch09 Elliptic Functions](Ch09_EllipticFunctions.md) | Tori; Weierstrass ℘; modular parameter τ; elliptic curves |
| [Ch10 Hyperbolic Geometry](Ch10_HyperbolicGeometry.md) | Upper half plane metric; PSL₂(ℝ) as isometries; modular surface |

## How each chapter is shaped

Every chapter contains, in roughly this order:

1. **Opening framing** — one paragraph on why this chapter exists,
   what changes.
2. **Picture** — an inline SVG showing the geometric content.
3. **Numerical exploration** — Lean `#eval` cells that compute the
   thing and let you see it.
4. **Formal sketch** — a Mathlib statement (often with `sorry`),
   pointing at the lemma that does the heavy lifting.
5. **Play** — parametric variations you can change and re-run.
6. **Prove it yourself** — three exercises, easy → medium → hard.
7. **Frontier link** — connections to modern math / physics / ML.

The total is ~80 cells across 10 chapters.  Each chapter is a few
hours of work if you do all the exercises.

## Prerequisites

- Reading: comfortable with calculus and undergraduate linear
  algebra.  Some familiarity with complex numbers helps but Ch01
  re-introduces them.
- Running cells: nothing — load this notebook in the browser kernel
  and click into a cell.
- Running the Mathlib examples: run `%load mathlib` in the first
  cell of each chapter.  See the notebook header for what to
  expect.

## Caveat

This is a playground, not a textbook.  The mathematical content is
faithful to the standard story but condensed; some proofs are
gestured at rather than spelled out.  For the canonical treatments:

- Needham, *Visual Complex Analysis* — the inspiration.
- Ahlfors, *Complex Analysis* — the standard graduate text.
- Stein–Shakarchi, *Complex Analysis* — accessible mid-level.

What this track adds beyond those: every result has a Lean / Mathlib
formal counterpart, and you can run the numerics live to test your
intuition before you trust the proof.
