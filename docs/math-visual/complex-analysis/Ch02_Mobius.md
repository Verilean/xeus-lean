# Chapter 2 — Möbius Transformations Up Close

In Chapter 1 we said:

$$
T(z) = \frac{a z + b}{c z + d}, \qquad ad - bc \neq 0.
$$

is the richest family of conformal self-maps of the Riemann sphere.
This chapter spends a whole notebook playing with that one family
because everything later — the Riemann sphere, hyperbolic geometry,
modular forms — is built on it.

```lean
%load mathlib
```

```lean
import Mathlib.Analysis.Complex.Basic
open Complex
```

## 2.1 — The four building blocks

Every Möbius transformation factors as a sequence of four atomic
moves:

1. **Translation**: $z \mapsto z + b$
2. **Rotation × scaling**: $z \mapsto a z$
3. **Inversion**: $z \mapsto 1/z$
4. (Repeat 1 + 2)

Concretely the formula $T(z) = (az+b)/(cz+d)$ factors as

$$
z \to z + d/c \to 1 / (z + d/c) \to (bc - ad)/c^2 \cdot 1/(z + d/c) \to (bc-ad)/c^2 \cdot 1/(z+d/c) + a/c
$$

(when $c \neq 0$).  The picture: a Möbius transformation is
"translate, invert, scale-and-rotate, translate again."

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
    <g stroke='#444' stroke-width='0.03' fill='none'>
      <path d='M 1.1 0.65 L 1.35 0.65'/>
      <path d='M 2.4 0.65 L 2.65 0.65'/>
      <path d='M 3.7 0.65 L 3.95 0.65'/>
      <path d='M 5.0 0.65 L 5.25 0.65'/>
    </g>
  </g>
</svg>"
```

So all the geometric weirdness of Möbius transformations comes from
exactly one of the four blocks — **inversion** — because the other
three are just rigid motions and uniform scaling.

## 2.2 — What inversion does to a line

A line through the origin maps under $z \mapsto 1/z$ to *itself*
(reflected across the real axis).  A line **not** through the origin
maps to a **circle through the origin**.  A circle not through the
origin maps to a circle not through the origin.

This is the "Möbius transformations send circles to circles" theorem,
where for "circle" you read "circle-or-line" (a line is a "circle of
infinite radius" passing through $\infty$).

Quick numerical check: the vertical line $\mathrm{Re}\, z = 1$.

```lean
-- Take eight points on the line Re z = 1, invert them, and look at
-- the absolute values.
def invertAll : List ℂ → List ℂ := List.map (1 / ·)

def line : List ℂ := [1, 1+I, 1+2*I, 1-I, 1-2*I, 1+0.5*I, 1-0.5*I, 1+10*I]

#eval invertAll line |>.map Complex.abs
-- All values < 1, clustering near 0.5 — they lie on a circle of
-- radius 1/2 centred at z = 1/2.  Try it: |w - 1/2| should equal 1/2.

#eval invertAll line |>.map fun w => Complex.abs (w - 0.5)
-- Each one is 0.5 (up to floating-point noise).  ✓
```

So the line `Re z = 1` inverts to the circle of radius $1/2$ centred
at $1/2$ — exactly as the theorem predicts, since $z = 1$ is on the
line and $1/1 = 1$ is on the circle.

## 2.3 — Play: try other lines and circles

Pick your own line through "somewhere not the origin" and see what
inversion does.

```lean
-- Replace `start` and `direction` to your taste.
def myLine (start direction : ℂ) (steps : Nat) : List ℂ :=
  List.range steps |>.map fun k => start + (k : ℝ) * direction

#eval invertAll (myLine (3 + I) I 8) |>.map fun w => Complex.abs (w - ⟨0.15, -0.05⟩)
-- The centre and radius you should expect are (1 / (2 ⋅ conj start))
-- and 1/(2 |start|) — but it's more fun to fit by eye.

-- Now a circle: parametrise z = c + r·exp(iθ) and invert it.
def myCircle (c : ℂ) (r : ℝ) (n : Nat) : List ℂ :=
  List.range n |>.map fun k =>
    let θ := 2 * Real.pi * (k : ℝ) / (n : ℝ)
    c + r * Complex.exp (θ * I)

#eval invertAll (myCircle 2 0.5 6) |>.map Complex.abs
-- All roughly the same value: the image is again a circle.
```

The interactive flavour: change `c` and `r`, see what happens to the
inverted radii.  When does the image pass through `0`?  When does it
*become* a line?

## 2.4 — Cross-ratio: the Möbius invariant

The cross-ratio of four distinct points $z_1, z_2, z_3, z_4$ is

$$
[z_1, z_2; z_3, z_4] = \frac{(z_1 - z_3)(z_2 - z_4)}{(z_1 - z_4)(z_2 - z_3)}.
$$

**Key fact:** Möbius transformations preserve cross-ratio.  Pick four
points, apply *any* Möbius transformation, the cross-ratio is the
same number.

```lean
def crossRatio (z₁ z₂ z₃ z₄ : ℂ) : ℂ :=
  ((z₁ - z₃) * (z₂ - z₄)) / ((z₁ - z₄) * (z₂ - z₃))

#eval crossRatio 1 2 3 4               -- 4/3

-- Apply T(z) = (z - i)/(z + i) and recompute:
def T (z : ℂ) : ℂ := (z - I) / (z + I)
#eval crossRatio (T 1) (T 2) (T 3) (T 4)  -- 4/3 ✓
```

Because three points determine a Möbius transformation, the
cross-ratio is *the* complete invariant: two configurations of four
points are Möbius-equivalent iff their cross-ratios match.

## 2.5 — Formal statement

In Mathlib's current naming (snapshot v4.28.0), the cross-ratio
preservation lives under `Mathlib.Analysis.SpecialFunctions.Complex`.
Naming drifts between versions; if your Mathlib doesn't have it under
this exact path, scout with:

```lean
#findDecl "crossRatio"    0 10
#findDecl "Mobius"        0 10
```

A formal sketch (un-`sorry`-able in plain text; finish it as an
exercise):

```lean
example (a b c d : ℂ) (h : a * d - b * c ≠ 0)
    (z₁ z₂ z₃ z₄ : ℂ) :
    let T : ℂ → ℂ := fun z => (a * z + b) / (c * z + d)
    crossRatio (T z₁) (T z₂) (T z₃) (T z₄) = crossRatio z₁ z₂ z₃ z₄ := by
  sorry  -- algebra; expand both sides and the (ad - bc) factors cancel
```

## 2.6 — Prove it yourself

1. Show that translation $z \mapsto z + b$ preserves cross-ratio.
   (Hint: each factor of the cross-ratio is a *difference*; differences
   are unaffected.)
2. Show that scaling $z \mapsto a z$ (with $a \neq 0$) preserves
   cross-ratio.  (Hint: each factor scales by the same $a$.)
3. (Hard) Show that inversion $z \mapsto 1/z$ preserves cross-ratio.
   This is the only block that's non-trivial; the cancellation is
   the heart of the cross-ratio's importance.

If you finish (3), you've effectively proven the §2.5 statement,
because every Möbius transformation factors through translations,
scalings, and one inversion.

## 2.7 — Frontier link

Why this matters beyond classical complex analysis:

- The cross-ratio is the invariant in **projective geometry over
  $\mathbb{C}$**; the same invariant shows up in computer vision
  (projective camera models) and string theory (worldsheet
  partition functions of free fields).
- The **modular group** $\mathrm{PSL}_2(\mathbb{Z})$ — Möbius
  transformations with integer entries and determinant $1$ — acts on
  the upper half plane and the resulting orbits classify elliptic
  curves.  This is the geometric bedrock under the Langlands program.
- Hyperbolic embeddings in ML (Poincaré embeddings, hyperbolic neural
  nets) live inside the unit disk with the Möbius action as their
  isometry group.

## What's next

Chapter 3 takes the inversion picture seriously and **adds a single
point at infinity** to compactify $\mathbb{C}$ into the Riemann
sphere — at which point "line" and "circle" become literally the
same object.
