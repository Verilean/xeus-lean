# Chapter 2 — Möbius Transformations Up Close

In Chapter 1 we said:

$$
T(z) = \frac{a z + b}{c z + d}, \qquad ad - bc \neq 0.
$$

is the richest family of conformal self-maps of the Riemann sphere.
This chapter spends a whole notebook playing with that one family
because everything later — the Riemann sphere, hyperbolic geometry,
modular forms — is built on it.

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
@[inline] def abs (a : ComplexF) : Float := (a.re * a.re + a.im * a.im).sqrt
def I : ComplexF := ⟨0, 1⟩
def ofReal (r : Float) : ComplexF := ⟨r, 0⟩
instance : Add ComplexF := ⟨add⟩
instance : Sub ComplexF := ⟨sub⟩
instance : Mul ComplexF := ⟨mul⟩
instance : Div ComplexF := ⟨div⟩
instance : OfNat ComplexF n where ofNat := ⟨Float.ofNat n, 0⟩
end ComplexF
open ComplexF
```

```lean
%load mathlib
```

```lean
import Mathlib.Analysis.Complex.Basic
```

## 2.1 — The four building blocks

Every Möbius transformation factors as a sequence of four atomic
moves:

1. **Translation**: $z \mapsto z + b$
2. **Rotation × scaling**: $z \mapsto a z$
3. **Inversion**: $z \mapsto 1/z$
4. (Repeat 1 + 2)

```lean
#html "<svg viewBox='0 0 6 1.5' width='540' style='background:#f4f4f8'>
  <g font-size='0.25' text-anchor='middle'>
    <rect x='0.1' y='0.3' width='1.0' height='0.7' fill='#e8e8f0' stroke='#888'/>
    <text x='0.6' y='0.78'>z</text>
    <rect x='1.4' y='0.3' width='1.0' height='0.7' fill='#7ec97e44' stroke='#3a3'/>
    <text x='1.9' y='0.78'>+ d/c</text>
    <rect x='2.7' y='0.3' width='1.0' height='0.7' fill='#f5a36a44' stroke='#c25'/>
    <text x='3.2' y='0.78'>1 / □</text>
    <rect x='4.0' y='0.3' width='1.0' height='0.7' fill='#7ec97e44' stroke='#3a3'/>
    <text x='4.5' y='0.78'>· k</text>
    <rect x='5.3' y='0.3' width='0.6' height='0.7' fill='#7ec97e44' stroke='#3a3'/>
    <text x='5.6' y='0.78'>+ a/c</text>
  </g>
</svg>"
```

All the geometric weirdness comes from one block — **inversion** —
because the other three are rigid motions and uniform scaling.

## 2.2 — What inversion does to a line

A line through the origin maps under $z \mapsto 1/z$ to *itself*
(reflected across the real axis).  A line **not** through the origin
maps to a **circle through the origin**.

```lean
-- A point z = 1 + ti on the vertical line Re z = 1,
-- inverted: 1/z = 1/(1+ti) = (1 - ti)/(1+t²).
-- We expect: every image lies on the circle |w - 1/2| = 1/2.
def linePoints : List ComplexF :=
  [⟨1, 0⟩, ⟨1, 1⟩, ⟨1, 2⟩, ⟨1, -1⟩, ⟨1, -2⟩, ⟨1, 0.5⟩, ⟨1, -0.5⟩, ⟨1, 10⟩]

def invertedPoints : List ComplexF := linePoints.map (fun z => 1 / z)

-- |w| should be < 1 (they live inside the circle of radius 1/2):
#eval invertedPoints.map abs

-- |w - 1/2| should equal 1/2 (they live ON that circle):
def centre : ComplexF := ofReal 0.5
#eval invertedPoints.map (fun w => abs (w - centre))
```

So the line `Re z = 1` inverts to the circle of radius $1/2$ centred
at $1/2$ — exactly as the theorem predicts.

## 2.3 — Play: try other lines and circles

Pick your own line through "somewhere not the origin" and see what
inversion does.

```lean
def myLine (start dir : ComplexF) (steps : Nat) : List ComplexF :=
  (List.range steps).map fun k => start + ⟨(Float.ofNat k), 0⟩ * dir

#eval (myLine (3 + I) I 6).map (fun z => 1 / z) |>.map abs
-- All similar in magnitude — they're on a circle.
```

The interactive flavour: change `start` and `dir`, see what happens
to the inverted magnitudes.  When does the image pass through `0`?
When does it *become* a line?

## 2.4 — Cross-ratio: the Möbius invariant

The cross-ratio of four distinct points $z_1, z_2, z_3, z_4$ is

$$
[z_1, z_2; z_3, z_4] = \frac{(z_1 - z_3)(z_2 - z_4)}{(z_1 - z_4)(z_2 - z_3)}.
$$

**Key fact:** Möbius transformations preserve cross-ratio.

```lean
def crossRatio (z₁ z₂ z₃ z₄ : ComplexF) : ComplexF :=
  ((z₁ - z₃) * (z₂ - z₄)) / ((z₁ - z₄) * (z₂ - z₃))

-- Pick four points and compute the cross-ratio.
#eval crossRatio 1 2 3 4         -- a fixed complex value

-- Apply T(z) = (z - i)/(z + i) and recompute:
def T (z : ComplexF) : ComplexF := (z - I) / (z + I)
#eval crossRatio (T 1) (T 2) (T 3) (T 4)
-- Should match the previous (modulo floating-point noise).
```

The cross-ratio is *the* complete Möbius invariant: two
configurations of four points are Möbius-equivalent iff their
cross-ratios match.

## 2.5 — Formal statement

```lean
-- Möbius transformation in Mathlib's `Complex`.  This statement
-- type-checks; the proof (cancellation algebra) is exercise 3.
example (a b c d : ℂ) (h : a * d - b * c ≠ 0)
    (z₁ z₂ z₃ z₄ : ℂ)
    (hne : (c * z₁ + d) ≠ 0 ∧ (c * z₂ + d) ≠ 0 ∧
           (c * z₃ + d) ≠ 0 ∧ (c * z₄ + d) ≠ 0) :
    True := by
  -- A full statement of "cross-ratio is preserved" needs a careful
  -- predicate on (T z₁, T z₂, T z₃, T z₄).  We leave it as the
  -- closing exercise; the type-checks-but-proves-trivially form
  -- here is the scaffolding.
  trivial
```

## 2.6 — Prove it yourself

1. (Easy) Show numerically that translation $z \mapsto z + b$
   preserves cross-ratio.  Each factor of the cross-ratio is a
   *difference*; differences are unaffected.
2. (Medium) Show that scaling $z \mapsto a z$ (with $a \neq 0$)
   preserves cross-ratio.  Each factor scales by the same $a$.
3. (Hard) Show that inversion $z \mapsto 1/z$ preserves cross-ratio.
   The cancellation is the heart of the cross-ratio's importance.

If you finish exercise 3, you've effectively proven the §2.5
statement, because every Möbius transformation factors through
translations, scalings, and one inversion.

## 2.7 — Frontier link

- The cross-ratio is the invariant in **projective geometry over
  $\mathbb{C}$**.  Same invariant shows up in computer vision and
  string theory's worldsheet partition functions.
- The **modular group** $\mathrm{PSL}_2(\mathbb{Z})$ acts on the
  upper half plane and the resulting orbits classify elliptic curves.
- Hyperbolic embeddings in ML (Poincaré embeddings, hyperbolic NNs)
  live inside the unit disk with the Möbius action as their isometry
  group.

## What's next

Chapter 3 takes the inversion picture seriously and **adds a single
point at infinity** to compactify $\mathbb{C}$ into the Riemann
sphere.
