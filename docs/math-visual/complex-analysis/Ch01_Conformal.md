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

```lean
%load mathlib
```

```lean
import Mathlib.Analysis.Complex.Basic
import Mathlib.Analysis.SpecialFunctions.Complex.Log
open Complex
```

## 1.1 — Multiplication is rotation × scaling

Pick a non-zero complex number $w$.  Multiplication by $w$, viewed as
a map $\mathbb{C} \to \mathbb{C}$, has two effects on every other
point $z$:

- scale $|z|$ by $|w|$,
- rotate the argument of $z$ by $\arg w$.

That's why complex multiplication is **conformal**: angles between two
incoming directions are preserved (both get rotated by the same
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
#eval (Complex.abs (1 + Complex.I))                -- √2
#eval ((1 + Complex.I) * (1 + Complex.I)).re        -- 0  (rotated to imag axis)
#eval ((1 + Complex.I) * (1 + Complex.I)).im        -- 2  (= |1+i|² = 2)
```

The vertical axis got mapped to the *negative real axis*: rotating
$\pi/2$ twice is $\pi$.  That's just $i^2 = -1$.

## 1.2 — Conformality, formally

A map $f: \mathbb{C} \to \mathbb{C}$ is **conformal at $z_0$** if its
derivative $f'(z_0) \neq 0$.  At any such point the local picture is
exactly multiplication by $f'(z_0)$: a rotation by $\arg f'(z_0)$ and
a scaling by $|f'(z_0)|$.  Angles are preserved, orientations are
preserved.

Formal statement from Mathlib:

```lean
-- A holomorphic function with nonzero derivative is conformal at z₀.
example (f : ℂ → ℂ) (z₀ : ℂ) (hf : DifferentiableAt ℂ f z₀)
    (h : deriv f z₀ ≠ 0) :
    ConformalAt f z₀ := by
  exact (hf.conformalAt_iff_isConformalMap).mpr ⟨deriv f z₀, h, rfl⟩
```

(If this proof doesn't go through your Mathlib snapshot, see the
`#findDecl "ConformalAt"` in §1.5 below — Mathlib's naming sometimes
drifts between versions.)

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
def mob (z : ℂ) : ℂ := (z - I) / (z + I)
#eval mob 0           -- (-i + 0)/(i + 0) = -1, on the unit circle ✓
#eval mob I           -- 0, the centre of the disk ✓
#eval Complex.abs (mob 1)   -- 1 ✓ (real line → unit circle)
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

## 1.5 — Lookups (if proofs don't go through)

```lean
-- Mathlib renames sometimes.  Use the helper to find current names.
#findDecl "Conformal" 0 10
#findDecl "Mobius"    0 10
```

## What's next

Chapter 2 will pursue Möbius transformations on the **Riemann
sphere** — the moment when "rotate and scale" suddenly has to include
a single point at infinity to make sense.
