# Chapter 10 — Hyperbolic Geometry

We end where we started: with Möbius transformations.  This time we
ask what *geometry* they preserve.  The answer is **hyperbolic
geometry**.

## Setup

```lean
structure ComplexF where
  re : Float
  im : Float
deriving Repr

namespace ComplexF
@[inline] def add (a b : ComplexF) : ComplexF := ⟨a.re + b.re, a.im + b.im⟩
@[inline] def sub (a b : ComplexF) : ComplexF := ⟨a.re - b.re, a.im - b.im⟩
@[inline] def mul (a b : ComplexF) : ComplexF :=
  ⟨a.re * b.re - a.im * b.im, a.re * b.im + a.im * b.re⟩
@[inline] def div (a b : ComplexF) : ComplexF :=
  let d := b.re * b.re + b.im * b.im
  ⟨(a.re * b.re + a.im * b.im) / d, (a.im * b.re - a.re * b.im) / d⟩
def I : ComplexF := ⟨0, 1⟩
def ofReal (r : Float) : ComplexF := ⟨r, 0⟩
instance : Add ComplexF := ⟨add⟩
instance : Sub ComplexF := ⟨sub⟩
instance : Mul ComplexF := ⟨mul⟩
instance : Div ComplexF := ⟨div⟩
instance : OfNat ComplexF n where ofNat := ⟨Float.ofNat n, 0⟩
end ComplexF
open ComplexF

def PI : Float := 3.141592653589793
```

## 10.1 — The hyperbolic metric on $\mathbb{H}$

$$
ds^2 = \frac{dx^2 + dy^2}{y^2}.
$$

Near the real axis, hyperbolic distance is large; high up, it's small.
The real axis is "at infinity."

```lean
-- Hyperbolic length of a vertical segment from i·a to i·b (a < b):
-- ∫_a^b dy/y = ln(b/a).
def hyperbolicLengthVertical (a b : Float) : Float := Float.log (b / a)

#eval hyperbolicLengthVertical 1.0 100.0        -- ln 100 ≈ 4.6
#eval hyperbolicLengthVertical 0.01 1.0         -- also ≈ 4.6 (symmetric)
#eval hyperbolicLengthVertical 0.001 1.0        -- ln 1000 ≈ 6.9
```

## 10.2 — Geodesics

Hyperbolic geodesics in $\mathbb{H}$:

- vertical lines, or
- semicircles in $\mathbb{H}$ with centres on the real axis.

```lean
#html "<svg viewBox='-1 -0.5 6 4' width='480' style='background:#f4f4f8'>
  <line x1='-1' y1='0' x2='5' y2='0' stroke='#3a3' stroke-width='0.04'/>
  <line x1='1' y1='0' x2='1' y2='3.5' stroke='#268' stroke-width='0.04'/>
  <path d='M 2 0 A 1.5 1.5 0 0 1 5 0' fill='none' stroke='#c25' stroke-width='0.04'/>
  <text x='2.6' y='1.9' fill='#c25' font-size='0.24'>semicircle geodesic</text>
  <text x='0.4' y='2.6' fill='#268' font-size='0.24'>vertical geodesic</text>
</svg>"
```

## 10.3 — Möbius transformations are isometries

$\mathrm{PSL}_2(\mathbb{R})$ is exactly the orientation-preserving
isometry group of $(\mathbb{H}, ds^2)$.  Real-coefficient Möbius
transformations preserve hyperbolic distances.

```lean
-- Hyperbolic distance between two points sharing the same real part:
def hyperbolicDistVertical (z₁ z₂ : ComplexF) : Float :=
  if z₁.re == z₂.re then
    Float.log (max z₁.im z₂.im / min z₁.im z₂.im)
  else 0.0  -- non-vertical case is harder; this is just for the demo

#eval hyperbolicDistVertical ⟨0, 1⟩ ⟨0, 5⟩      -- ln 5 ≈ 1.609

-- Apply z → z + 1 (a real translation, an isometry):
def shift (z : ComplexF) : ComplexF := z + 1
#eval hyperbolicDistVertical (shift ⟨0, 1⟩) (shift ⟨0, 5⟩)
-- Same value, because we only shifted real parts.
```

## 10.4 — The Poincaré disk model

The Cayley transform $T(z) = (z-i)/(z+i)$ sends $\mathbb{H}$ to the
unit disk with the hyperbolic metric

$$
ds^2 = \frac{4 \,|dw|^2}{(1 - |w|^2)^2}.
$$

Escher's *Circle Limit* is a tiling of this disk by hyperbolic
triangles of equal area.

## 10.5 — The modular surface

$\mathcal{M}_1 = \mathbb{H} / \mathrm{SL}_2(\mathbb{Z})$.  A canonical
fundamental domain:
$$
\mathcal{F} = \{ \tau : |\mathrm{Re}\,\tau| \le 1/2, |\tau| \ge 1 \}.
$$
Its hyperbolic area is $\pi/3$ — finite!

```lean
-- Numerical: ∫_F dx dy / y² ≈ π/3.
def modularDomainArea : Float := Id.run do
  let M : Nat := 800
  let xMin : Float := -0.5
  let dx : Float := 1.0 / Float.ofNat M
  let yMax : Float := 30.0
  let mut acc : Float := 0
  for i in [:M] do
    let x : Float := xMin + (Float.ofNat i + 0.5) * dx
    let yLow : Float := (max (1.0 - x*x) 0.0).sqrt
    if yLow > 0.001 then
      -- ∫_{yLow}^{yMax} dy / y² = 1/yLow - 1/yMax
      acc := acc + dx * (1.0 / yLow - 1.0 / yMax)
  pure acc

#eval modularDomainArea         -- ≈ 1.047 = π/3
#eval PI / 3.0
```

## 10.6 — Formal sketch

```lean
%load mathlib
```

```lean
import Mathlib.Analysis.Complex.UpperHalfPlane.Basic

example : Type := UpperHalfPlane

example : Group (Matrix.SpecialLinearGroup (Fin 2) ℤ) := inferInstance
```

## 10.7 — Prove it yourself

1. Verify the metric invariance numerically: apply $T(z) = z + 1$
   and $T(z) = -1/z$ to two points and check that hyperbolic
   distance is preserved.  These two generate $\mathrm{SL}_2(\mathbb{Z})$.
2. Show the Cayley transform is an isometry between
   $\mathbb{H}$ (upper-half-plane metric) and the Poincaré disk.
3. (Hard) Compute the hyperbolic area of an "ideal triangle" (all
   three vertices on the real axis).  Show the area is $\pi$,
   regardless of which three vertices.

## 10.8 — Frontier link

- **Selberg trace formula** — spectral side of Langlands.
- **Quantum chaos** on the modular surface.
- **Mirzakhani's Weil–Petersson volumes** on moduli of bordered
  hyperbolic surfaces (Fields medal 2014).

## 10.9 — Recap of the whole arc

- Ch1 — multiplication = rotation × scaling
- Ch2 — Möbius transformations
- Ch3 — Riemann sphere
- Ch4 — contour integrals
- Ch5 — residues for real integrals
- Ch6 — argument principle
- Ch7 — rigidity (smooth + analytic + identity)
- Ch8 — Riemann mapping (everything ≅ disk…)
- Ch9 — except tori (elliptic functions, modular forms)
- Ch10 — and $\mathbb{H}$ has its own hyperbolic geometry.

The first object (rotations of $\mathbb{C}$) is the last object
(isometries of $\mathbb{H}$), specialised to real coefficients.

## Where to go next

- Mathlib's `Mathlib.Analysis.Complex.*` for the formal proofs.
- Mathlib's `Mathlib.NumberTheory.ModularForms` for Langlands flavour.
- Needham, *Visual Complex Analysis* (the canonical book; no Lean).
- The companion tracks: `manifolds/`, `category/`, `optimal-transport/`
  (when they land).
