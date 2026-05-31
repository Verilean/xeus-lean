# Chapter 10 — Hyperbolic Geometry

We end where we started: with the Möbius transformations of
chapters 2 and 3.  This time we ask what *geometry* they preserve.

The answer is **hyperbolic geometry** — the non-Euclidean geometry
in which the upper half plane $\mathbb{H} = \{z : \mathrm{Im}\, z >
0\}$ is the canonical model, every Möbius transformation in
$\mathrm{PSL}_2(\mathbb{R})$ is an isometry, and the modular
surface $\mathbb{H} / \mathrm{SL}_2(\mathbb{Z})$ from chapter 9
acquires a finite-area Riemannian structure.

Complex analysis ends as the gateway to hyperbolic geometry,
arithmetic groups, the Langlands program, and a sizeable chunk of
modern geometry-of-numbers.

```lean
%load mathlib
```

```lean
import Mathlib.Analysis.Complex.Basic
open Complex Real
```

## 10.1 — The hyperbolic metric on $\mathbb{H}$

Define the **hyperbolic distance element** on $\mathbb{H}$ by

$$
ds^2 = \frac{dx^2 + dy^2}{y^2}.
$$

A horizontal segment near the real axis has *huge* hyperbolic
length, even though its Euclidean length is small.  A segment near
the "top" of the upper half plane is *short* in hyperbolic
distance.  As you approach the real axis you have to traverse
infinite hyperbolic distance — the real axis is "at infinity."

```lean
-- Hyperbolic length of a vertical segment from i·a to i·b
-- (a < b).  By integration: ∫_a^b dy/y = ln(b/a).
def hyperbolicLengthVertical (a b : ℝ) : ℝ := Real.log (b / a)

#eval hyperbolicLengthVertical 1 100        -- ln 100 ≈ 4.6
#eval hyperbolicLengthVertical 0.01 1       -- also ln 100 ≈ 4.6 (symmetric)
#eval hyperbolicLengthVertical 0.001 1      -- ln 1000 ≈ 6.9
```

The closer you get to the real axis, the more hyperbolic distance
piles up.

## 10.2 — Geodesics

**Hyperbolic geodesics** in $\mathbb{H}$ are:

- vertical lines (segments of the form $\{x = a\}$), or
- semicircles in $\mathbb{H}$ with their centres on the real axis.

That second case is the surprising one.  A "straight line" between
two non-vertically-aligned points $z_1, z_2 \in \mathbb{H}$ is the
arc of a circle perpendicular to the real axis passing through both.

```lean
#html "<svg viewBox='-1 -0.5 6 4' width='480' style='background:#f4f4f8'>
  <line x1='-1' y1='0' x2='5' y2='0' stroke='#3a3' stroke-width='0.04'/>
  <text x='-0.95' y='-0.15' fill='#3a3' font-size='0.22'>ℝ (boundary)</text>
  <!-- vertical geodesic -->
  <line x1='1' y1='0' x2='1' y2='3.5' stroke='#268' stroke-width='0.04'/>
  <!-- semicircle geodesic with centre on real axis -->
  <path d='M 2 0 A 1.5 1.5 0 0 1 5 0' fill='none' stroke='#c25' stroke-width='0.04'/>
  <circle cx='2' cy='0' r='0.05' fill='#444'/>
  <circle cx='5' cy='0' r='0.05' fill='#444'/>
  <text x='2.6' y='1.9' fill='#c25' font-size='0.24'>semicircle geodesic</text>
  <text x='0.4' y='2.6' fill='#268' font-size='0.24'>vertical geodesic</text>
</svg>"
```

## 10.3 — Möbius transformations are isometries

For $T = \begin{pmatrix}a & b \\ c & d\end{pmatrix} \in
\mathrm{SL}_2(\mathbb{R})$, the action
$$
T \cdot z = \frac{az + b}{cz + d}
$$
preserves the hyperbolic metric.  In particular:

- straight (Euclidean) lines and semicircles get mapped to other
  geodesics,
- angles between intersecting geodesics are preserved (these are
  Möbius transformations, so they're conformal!),
- hyperbolic distances are preserved.

The group of orientation-preserving hyperbolic isometries is
$\mathrm{PSL}_2(\mathbb{R}) = \mathrm{SL}_2(\mathbb{R})/\{\pm I\}$
— exactly the Möbius transformations with real coefficients.

The full isometry group adds reflections; in matrix terms,
$\mathrm{PGL}_2(\mathbb{R})$.

```lean
-- An isometry test: apply Möbius transformation and verify
-- the hyperbolic distance is preserved.
def hyperbolicDistVertical (z₁ z₂ : ℂ) : ℝ :=
  if z₁.re == z₂.re then
    Real.log (max z₁.im z₂.im / min z₁.im z₂.im)
  else 0  -- placeholder; non-vertical case is harder

#eval hyperbolicDistVertical ⟨0, 1⟩ ⟨0, 5⟩      -- ln 5 ≈ 1.609

-- Apply z → z + 1 (a real translation, an isometry):
def shift (z : ℂ) : ℂ := z + 1
#eval hyperbolicDistVertical (shift ⟨0, 1⟩) (shift ⟨0, 5⟩)
-- Same answer.  ✓ (because we only shifted real parts)
```

## 10.4 — The Poincaré disk model

You can transplant $\mathbb{H}$ to the unit disk via the Cayley
transform from §8.2:
$$
T(z) = \frac{z - i}{z + i}.
$$
The image is the **Poincaré disk** $\{|w| < 1\}$, on which the
hyperbolic metric is
$$
ds^2 = \frac{4 \, |dw|^2}{(1 - |w|^2)^2}.
$$

Geodesics in the Poincaré disk: diameters and arcs of circles
perpendicular to the boundary.  Famous artwork by M.C. Escher
("Circle Limit") tiles the Poincaré disk with hyperbolic triangles
of equal area — they look smaller and smaller toward the boundary
because the metric blows up there.

## 10.5 — The modular surface

Chapter 9 introduced the moduli space
$\mathcal{M}_1 = \mathbb{H} / \mathrm{SL}_2(\mathbb{Z})$.  With the
hyperbolic metric on $\mathbb{H}$, the quotient inherits a hyperbolic
structure too.  A canonical fundamental domain is
$$
\mathcal{F} = \{ \tau \in \mathbb{H} :
    |\mathrm{Re}\,\tau| \le \tfrac12, \;\; |\tau| \ge 1 \}.
$$

Its **hyperbolic area** is $\pi/3$ — finite!  Even though
$\mathcal{F}$ stretches up to infinity in the Euclidean picture, the
metric $1/y^2$ makes it have finite measure.

This is why the modular surface is special: it's a non-compact but
finite-volume hyperbolic surface, the simplest example of an
**arithmetic hyperbolic 2-manifold**.

```lean
-- Numerical: area of F under dx dy / y² over the fundamental domain.
def modularDomainArea : ℝ := Id.run do
  let M : Nat := 800
  let xMin := -0.5
  let xMax := 0.5
  let dx := (xMax - xMin) / (M : ℝ)
  let yMax := 30.0
  let mut acc : ℝ := 0
  for i in [:M] do
    let x : ℝ := xMin + (i : ℝ + 0.5) * dx
    let yLow : ℝ := Real.sqrt (max (1 - x*x) 0)
    -- ∫_{yLow}^{yMax} dy / y² = 1/yLow - 1/yMax
    if yLow > 0.001 then
      acc := acc + dx * (1 / yLow - 1 / yMax)
  pure acc

#eval modularDomainArea
-- Should land near π/3 ≈ 1.047
#eval Real.pi / 3
```

## 10.6 — Formal sketch

Mathlib has the upper half plane with its hyperbolic structure
(`UpperHalfPlane`), and the modular group action.

```lean
example : Type := UpperHalfPlane

-- The modular group SL₂(ℤ):
example : Group (Matrix.SpecialLinearGroup (Fin 2) ℤ) := inferInstance

-- A point in the standard fundamental domain (e.g. τ = i):
example : UpperHalfPlane := ⟨I, by simp⟩
```

The "hyperbolic metric is invariant under PSL₂(ℝ)" theorem is in
Mathlib in the form of a Riemannian metric on $\mathbb{H}$.  Finding
it cleanly:

```lean
#findDecl "UpperHalfPlane" "metric" 0 10
```

## 10.7 — Prove it yourself

1. (Easy) Verify the metric invariance numerically: apply
   $T(z) = (z + 1)$ and $T(z) = -1/z$ to two points in $\mathbb{H}$
   and check that the hyperbolic distance between them is the same
   before and after.  These two transformations generate
   $\mathrm{SL}_2(\mathbb{Z})$.
2. (Medium) Show that the Cayley transform from §10.4 is an
   isometry between the upper-half-plane hyperbolic metric and the
   Poincaré disk hyperbolic metric.
3. (Hard) Compute the hyperbolic area of a triangle in the upper
   half plane with vertices at three points on the real axis (an
   "ideal triangle").  Show the area is $\pi$, regardless of which
   three points you pick — a feature unique to hyperbolic
   geometry.

## 10.8 — Frontier link

- **Selberg trace formula.**  The spectrum of the Laplacian on the
  modular surface relates to closed geodesics — the analogue of
  Poisson summation in hyperbolic geometry.  Sits underneath the
  Langlands program.
- **Quantum chaos.**  The modular surface is the canonical example
  of a quantum-chaotic system; its eigenfunctions ("Maass forms")
  are conjecturally distributed quantum-uniformly — one of the few
  arithmetic models where this is provable for special cases.
- **Random hyperbolic surfaces.**  Mirzakhani's Fields-medal work
  computes Weil-Petersson volumes of moduli spaces of bordered
  hyperbolic surfaces — a direct generalisation of "area = $\pi/3$"
  to arbitrary genus.

## 10.9 — Recap of the whole arc

Ten chapters in, the path was:

- Ch1 — multiplication is rotation + scaling
- Ch2 — Möbius transformations
- Ch3 — Riemann sphere (compactify)
- Ch4 — contour integrals (topology-aware calculus)
- Ch5 — residues (real integrals via imaginary paths)
- Ch6 — argument principle (count without finding)
- Ch7 — rigidity (holomorphic is automatically smooth + analytic)
- Ch8 — Riemann mapping theorem (everything looks like the disk…)
- Ch9 — except tori, which give elliptic functions and modular forms
- Ch10 — and the upper half plane has its own hyperbolic geometry

Each chapter loaded picture → numerics → formal Mathlib → exercises.
The final chapter loops back: the very first object (rotations of
$\mathbb{C}$) is the very last (isometries of $\mathbb{H}$),
specialised to the real-coefficient case.

## Where to go next

If you came here for **proof assistant work**, the obvious next
stops are:
- Mathlib's Complex Analysis namespace (start with
  `Mathlib.Analysis.Complex.Basic` and follow imports).
- The Langlands-flavored material in
  `Mathlib.NumberTheory.ModularForms`.
- The growing body of work on classification of Riemann surfaces.

If you came here for **mathematics** in the broader sense:
- The companion `manifolds/` chapters (when they land) take the
  Riemannian geometry seriously.
- The `category/` chapters tie geometric examples to abstract
  structures (sheaves, schemes, …).
- Original Tristan Needham, *Visual Complex Analysis* — same
  spirit, less Lean.
