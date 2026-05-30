# Chapter 3 — The Riemann Sphere

The complex plane has a hole at infinity that inversion keeps falling
through.  $1/z$ at $z = 0$ is "undefined", and that's annoying:
otherwise nice maps acquire artificial discontinuities.

The fix is to **add a single point at infinity** and turn the
resulting space into a sphere — the **Riemann sphere**
$\hat{\mathbb{C}} = \mathbb{C} \cup \{\infty\}$.  On the sphere there's
no longer a "centre" and a "rim"; "near 0" and "near $\infty$" are
just two charts on the same closed surface.

```lean
%load mathlib
```

```lean
import Mathlib.Analysis.Complex.Basic
open Complex
```

## 3.1 — Stereographic projection: the picture

Place a unit sphere $S^2$ sitting on the plane at the origin.  From
the north pole, project lines down to the plane: each line hits the
sphere at one point and the plane at one point.  That bijection is
**stereographic projection**.

The south pole maps to $0$.  The equator maps to the unit circle.
The north pole — the only point with no plane image — is what we
*call* $\infty$.

```lean
#html "<svg viewBox='-2.5 -2.5 5 5' width='400' style='background:#f4f4f8'>
  <!-- the sphere (oblique view) -->
  <ellipse cx='0' cy='-0.7' rx='1.4' ry='1.4' fill='none' stroke='#666'/>
  <ellipse cx='0' cy='-0.7' rx='1.4' ry='0.4' fill='none' stroke='#666' stroke-dasharray='0.1,0.1'/>
  <!-- plane: thick line at the bottom -->
  <line x1='-2.3' y1='1.2' x2='2.3' y2='1.2' stroke='#3a3' stroke-width='0.05'/>
  <text x='1.8' y='1.5' fill='#3a3' font-size='0.22'>plane</text>
  <!-- north pole -->
  <circle cx='0' cy='-2.1' r='0.08' fill='#c25'/>
  <text x='0.15' y='-2.0' fill='#c25' font-size='0.22'>N = ∞</text>
  <!-- south pole = origin -->
  <circle cx='0' cy='0.7' r='0.08' fill='#3a3'/>
  <text x='0.15' y='0.85' fill='#3a3' font-size='0.22'>S = 0</text>
  <!-- a projection ray -->
  <line x1='0' y1='-2.1' x2='2' y2='1.2' stroke='#888' stroke-dasharray='0.05,0.05'/>
  <circle cx='1.06' cy='-0.5' r='0.07' fill='#268'/>
  <circle cx='2' cy='1.2' r='0.07' fill='#268'/>
  <text x='2.1' y='1.1' fill='#268' font-size='0.18'>z</text>
</svg>"
```

Two consequences:

1. **Lines and circles are the same object.**  A line in the plane is
   a circle on the sphere that passes through the north pole.
2. **$\infty$ is just a point.**  No more "approaching infinity" — you
   can walk through the north pole and come back out at $-\infty$ in
   any direction.

## 3.2 — Inversion is rotation of the sphere

Here's the punchline that Chapter 2 was setting up: the map
$z \mapsto 1/z$ on the plane is exactly the *rotation* of the sphere
by $\pi$ around the horizontal axis.

That's why inversion sends circles to circles: rotations send circles
to circles.  No more case analysis ("a line through the origin maps
to itself, a line not through the origin maps to a circle...") —
it's all the same operation.

Numerically (the sphere coordinates take some setup), we'll just verify
the inversion property:

```lean
-- Six points evenly spaced on the unit circle, then inverted.
-- They should map back to six points on the unit circle (and in fact
-- in reverse order, since inversion = rotation by π).
def unitCircle (n : Nat) : List ℂ :=
  List.range n |>.map fun k =>
    Complex.exp ((2 * Real.pi * (k : ℝ) / (n : ℝ)) * I)

#eval unitCircle 6 |>.map Complex.abs        -- six 1's
#eval (unitCircle 6).map (1 / ·) |>.map Complex.abs   -- six 1's again ✓
```

## 3.3 — The Möbius action is rotations of the sphere

Every Möbius transformation that fixes the unit circle (in particular,
those with $|a|^2 + |b|^2 = |c|^2 + |d|^2$ and $\bar a d - \bar b c$
real…  the exact algebraic conditions are fiddly) is a rotation of
the sphere — i.e. an element of $\mathrm{SO}(3)$ in disguise.

The full Möbius group $\mathrm{PSL}_2(\mathbb{C})$ is twice the size:
it's the group of all conformal automorphisms of the sphere, which
includes both rotations and "boost-like" maps that move points
towards or away from the poles.

## 3.4 — Formal sketch

Mathlib doesn't ship a "Riemann sphere" type as such — it would
typically use `OnePoint ℂ` (the one-point compactification of $\mathbb{C}$)
from `Mathlib.Topology.Compactification.OnePoint`.

```lean
import Mathlib.Topology.Compactification.OnePoint

-- The Riemann sphere as a topological space:
example : Type := OnePoint ℂ

-- It's a compact Hausdorff space:
example : CompactSpace (OnePoint ℂ) := inferInstance
```

The conformal-structure-on-the-sphere theorems are scattered around
`Mathlib.Analysis.SpecialFunctions.Complex.*` — use `#findDecl` to
hunt them down.

## 3.5 — Play: where does $\infty$ go?

Under $T(z) = (az + b)/(cz + d)$:

- when $c \neq 0$: $T(\infty) = a/c$ (the leading coefficients win)
- when $c = 0$: $T(\infty) = \infty$ (no division, no compactification
  needed)

That mental rule plus "$T(-d/c) = \infty$" tells you the full
behaviour of any Möbius transformation as a sphere map.

```lean
-- For T(z) = (2z + 1)/(z - 1):
def T (z : ℂ) : ℂ := (2 * z + 1) / (z - 1)
#eval T 10000        -- ≈ 2 (the limit as z → ∞: a/c = 2)
#eval T 1.0001       -- huge magnitude (we're near z = d/c, which → ∞)
```

## 3.6 — Prove it yourself

1. Show that the unit circle $|z| = 1$ in $\mathbb{C}$ corresponds
   under stereographic projection to the equator of the sphere.
   (Geometry: the projection ray from $(0, 0, 1)$ to $(x, y, 0)$
   meets the sphere at...)
2. Verify that $z \mapsto 1/\bar z$ is the *reflection* of the sphere
   across the equator.  (Hint: combine inversion with conjugation.)
3. (Hard) Show that *every* Möbius transformation extends continuously
   to a self-map of $\hat{\mathbb{C}} = $ `OnePoint ℂ`.

## 3.7 — Frontier link

The "no centre, no infinity" character of the sphere is the geometric
intuition behind **renormalisation** in physics: a scale at which
"infinity" looks like nothing special is the scale at which the
theory makes sense.  In ML, the spherical perspective resurfaces in
**spherical CNNs** (rotation-equivariant on $S^2$) and in **density
estimation on compact manifolds** generally.

## What's next

Chapter 4 will use the sphere to give a properly geometric account of
**contour integration**: closing a contour on the sphere makes the
"residues at infinity" come out as just one more residue.
