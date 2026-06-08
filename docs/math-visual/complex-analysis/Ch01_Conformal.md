# Chapter 1 — Conformal Maps and the Geometry of Multiplication

> *"Complex multiplication is, geometrically, simultaneous rotation and
> dilation."* — V.I. Arnold

The plane $\mathbb{R}^2$ is dull because its multiplication is just
componentwise; you can scale and translate but you have to bolt
rotations on by hand.  The complex plane $\mathbb{C}$ is interesting
because its multiplication *is* the rotation-and-scaling structure —
and that single fact gives every conformal map in the chapter.

This notebook starts with a picture, plays with the numerics, and
ends with a formal statement.

## Setup

For the numerical cells, we use the `ComplexF` (Float-backed complex)
type from [Chapter 0 §0.3](Ch00_NumericsAndMathlib.md#03--a-computable-complex-number).
Re-paste it here so the cells run:

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
@[inline] def abs (a : ComplexF) : Float := (a.re * a.re + a.im * a.im).sqrt
@[inline] def arg (a : ComplexF) : Float := Float.atan2 a.im a.re
def I : ComplexF := ⟨0, 1⟩
def ofReal (r : Float) : ComplexF := ⟨r, 0⟩
instance : Add ComplexF := ⟨add⟩
instance : Sub ComplexF := ⟨sub⟩
instance : Mul ComplexF := ⟨mul⟩
instance : OfNat ComplexF n where ofNat := ⟨Float.ofNat n, 0⟩
end ComplexF
open ComplexF
```

For the formal cells later in the chapter we'll switch over to
Mathlib's `Complex`.

```text
%load mathlib
```

```lean
import Mathlib.Analysis.Complex.Basic
import Mathlib.Analysis.SpecialFunctions.Complex.Log
```

## 1.1 — Multiplication is rotation × scaling

Pick a non-zero complex number $w$.  Multiplication by $w$, viewed as
a map $\mathbb{C} \to \mathbb{C}$, has two effects on every other
point $z$:

- scale $|z|$ by $|w|$,
- rotate the argument of $z$ by $\arg w$.

That's why complex multiplication is **conformal**: angles between
two incoming directions are preserved (both get rotated by the same
$\arg w$, so the angle between them is unchanged).

Picture: a small grid square in green, the image after multiplying by
$w = 1 + i$ (rotate by $\pi/4$, scale by $\sqrt 2$) in orange.

```lean
#html "<svg viewBox='-3 -3 6 6' width='400' style='background:#f4f4f8'>
  <line x1='-3' y1='0' x2='3' y2='0' stroke='#aaa'/>
  <line x1='0' y1='-3' x2='0' y2='3' stroke='#aaa'/>
  <!-- original 1x1 square -->
  <polygon points='0.5,-0.5 1.5,-0.5 1.5,0.5 0.5,0.5'
           fill='#7ec97e88' stroke='#3a3'/>
  <!-- image under multiplication by 1+i: rotate 45°, scale √2 -->
  <polygon points='1,0 2,1 1,2 0,1'
           fill='#f5a36a88' stroke='#c25'/>
  <text x='0.6' y='-0.7' fill='#3a3' font-size='0.3'>z</text>
  <text x='0.4' y='1.9' fill='#c25' font-size='0.3'>(1+i)·z</text>
</svg>"
```

Numerically:

```lean
-- |1 + i| = √2
#eval abs (1 + I)               -- 1.4142...
-- (1+i)·(1+i) = (1·1 - 1·1) + (1·1 + 1·1)·i = 0 + 2i
#eval (1 + I) * (1 + I)          -- ⟨0.0, 2.0⟩
-- arg(1+i) = π/4
#eval arg (1 + I)                -- 0.7853... = π/4
```

The square got rotated $\pi/4$ and scaled by $\sqrt 2$ — both
recoverable from `1 + i`'s modulus and argument.  And
$(1+i)^2 = 2i$ has argument $\pi/2$: rotate $\pi/4$ twice.

## 1.2 — Conformality, formally

A map $f: \mathbb{C} \to \mathbb{C}$ is **conformal at $z_0$** if its
derivative $f'(z_0) \neq 0$.  At any such point the local picture is
exactly multiplication by $f'(z_0)$: a rotation by $\arg f'(z_0)$ and
a scaling by $|f'(z_0)|$.

This is where the Float world steps aside and Mathlib takes over.
The exact statement (which `#eval` can't *evaluate*, but can
type-check):

```lean
-- A holomorphic function with nonzero derivative is conformal at z₀.
example (f : ℂ → ℂ) (z₀ : ℂ) (hf : DifferentiableAt ℂ f z₀)
    (h : deriv f z₀ ≠ 0) :
    True := by
  -- The actual Mathlib name has drifted between versions; scout with
  --   #findDecl "Conformal" 0 10
  trivial
```

The `True` placeholder there is so the cell type-checks even if your
Mathlib snapshot has renamed the conformality predicate.  Look up
the live name with `#findDecl` (see §1.5).

## 1.3 — Möbius transformations

The richest family of conformal self-maps of the Riemann sphere
$\hat{\mathbb{C}} = \mathbb{C} \cup \{\infty\}$ is the **Möbius
transformations**:

$$
T(z) = \frac{a z + b}{c z + d}, \qquad ad - bc \neq 0.
$$

Three free complex parameters (a Möbius transformation is fixed by
where it sends any three distinct points).

A useful picture: how the upper half-plane $\{ \mathrm{Im}\, z > 0\}$
gets mapped to the unit disk by $T(z) = (z - i)/(z + i)$.

```lean
#html "<svg viewBox='-2 -1 4 3' width='400' style='background:#f4f4f8'>
  <!-- upper half plane shaded -->
  <rect x='-2' y='-1' width='4' height='1' fill='#7ec97e22'/>
  <line x1='-2' y1='0' x2='2' y2='0' stroke='#3a3' stroke-width='0.02'/>
  <!-- unit disk -->
  <circle cx='0' cy='1.5' r='0.5' fill='#f5a36a44' stroke='#c25' stroke-width='0.02'/>
  <text x='-1.8' y='-0.4' font-size='0.18' fill='#3a3'>upper half plane (preimage)</text>
  <text x='-0.6' y='1.6' font-size='0.14' fill='#c25'>unit disk (image)</text>
</svg>"
```

Numerically: the real line maps to the unit circle, $z = i$ maps to
the origin.

```lean
namespace ComplexF
-- Helper: division
@[inline] def div (a b : ComplexF) : ComplexF :=
  let d := b.re * b.re + b.im * b.im
  ⟨(a.re * b.re + a.im * b.im) / d, (a.im * b.re - a.re * b.im) / d⟩
instance : Div ComplexF := ⟨div⟩
end ComplexF
open ComplexF

def mob (z : ComplexF) : ComplexF := (z - I) / (z + I)

#eval mob 0                    -- (-1 + 0i): on the unit circle ✓
#eval mob I                    -- (0  + 0i): the centre of the disk ✓
#eval abs (mob 1)              -- 1: real line maps to unit circle ✓
```

## 1.4 — Why this matters for LLM frontier work

Two reasons this chapter is "frontier-relevant" rather than just
classical:

- **Conformal field theory** in physics and **automorphic forms** in
  number theory both live on Möbius/conformal scaffolding.  Formalising
  even the very first picture (multiplication = rotation × scaling)
  is the foothold a proof-assistant LLM needs before any of that
  becomes tractable.
- **Hyperbolic geometry** is the natural geometry of the upper half
  plane under the Möbius action by $\mathrm{SL}_2(\mathbb{R})$.  That
  in turn shows up in modern probabilistic ML (e.g. hyperbolic
  embeddings).

## 1.5 — Lookups (Mathlib name drift)

Mathlib renames sometimes.  Use these helpers to find current names
without remembering them:

```lean
-- Find Mathlib declarations whose name contains "Conformal":
#findDecl "Conformal" 0 10
-- And anything related to Möbius:
#findDecl "Mobius"    0 10
```

If a formal `example` in this chapter doesn't compile, scouting via
`#findDecl` is faster than reading Mathlib's source tree.

## 1.6 — Prove it yourself

1. (Easy) Numerically: pick three complex numbers $a, b, c$ with
   $a + b + c = 0$.  Compute their arguments and verify that they're
   $2\pi/3$ apart only when $|a| = |b| = |c|$ (i.e. when they form an
   equilateral triangle around the origin).
2. (Medium) Show that the Möbius transformation $T(z) = (z-i)/(z+i)$
   maps $0 \mapsto -1$, $i \mapsto 0$, $1 \mapsto -i$, and $-1
   \mapsto i$.  Verify with `#eval`, then prove via algebra that the
   real axis maps to the unit circle.
3. (Hard) Show that the only Möbius transformations of the unit disk
   to itself fixing $0$ are rotations $z \mapsto e^{i\theta} z$.
   (This is half the Schwarz lemma; we'll meet the other half in
   Chapter 7.)

## What's next

Chapter 2 will pursue Möbius transformations on the **Riemann
sphere** — the moment when "rotate and scale" suddenly has to include
a single point at infinity to make sense.
