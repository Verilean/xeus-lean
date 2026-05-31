# Chapter 3 — The Riemann Sphere

The complex plane has a hole at infinity that inversion keeps falling
through.  $1/z$ at $z = 0$ is "undefined", and that's annoying:
otherwise nice maps acquire artificial discontinuities.

The fix is to **add a single point at infinity** and turn the
resulting space into a sphere — the **Riemann sphere**
$\hat{\mathbb{C}} = \mathbb{C} \cup \{\infty\}$.

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
@[inline] def exp (a : ComplexF) : ComplexF :=
  let m := a.re.exp; ⟨m * a.im.cos, m * a.im.sin⟩
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
import Mathlib.Topology.Compactification.OnePoint
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
  <ellipse cx='0' cy='-0.7' rx='1.4' ry='1.4' fill='none' stroke='#666'/>
  <ellipse cx='0' cy='-0.7' rx='1.4' ry='0.4' fill='none' stroke='#666' stroke-dasharray='0.1,0.1'/>
  <line x1='-2.3' y1='1.2' x2='2.3' y2='1.2' stroke='#3a3' stroke-width='0.05'/>
  <text x='1.8' y='1.5' fill='#3a3' font-size='0.22'>plane</text>
  <circle cx='0' cy='-2.1' r='0.08' fill='#c25'/>
  <text x='0.15' y='-2.0' fill='#c25' font-size='0.22'>N = ∞</text>
  <circle cx='0' cy='0.7' r='0.08' fill='#3a3'/>
  <text x='0.15' y='0.85' fill='#3a3' font-size='0.22'>S = 0</text>
</svg>"
```

Two consequences:

1. **Lines and circles are the same object.** A line in the plane
   is a circle on the sphere that passes through the north pole.
2. **$\infty$ is just a point.**

## 3.2 — Inversion is rotation of the sphere

$z \mapsto 1/z$ on the plane is exactly rotation of the sphere by
$\pi$ around the horizontal axis.

Numerically: six points evenly spaced on the unit circle, inverted,
should land back on the unit circle.

```lean
-- Six points on the unit circle: z = e^{2πik/6}
def unitCircle (n : Nat) : List ComplexF :=
  (List.range n).map fun k =>
    let θ : Float := 2.0 * 3.141592653589793 * (Float.ofNat k) / (Float.ofNat n)
    (ofReal θ * I).exp

#eval (unitCircle 6).map abs                -- six 1's (up to FP noise)
#eval ((unitCircle 6).map (fun z => 1 / z)).map abs   -- also six 1's ✓
```

## 3.3 — The Möbius action on the sphere

Every Möbius transformation extends to a self-map of the sphere.  The
rules:

- when $c \neq 0$: $T(\infty) = a/c$ and $T(-d/c) = \infty$
- when $c = 0$:    $T(\infty) = \infty$ (affine map)

For $T(z) = (2z + 1)/(z - 1)$ we should expect $T(\infty) = 2$ and
$T(1) \to \infty$.

```lean
def T (z : ComplexF) : ComplexF := (2 * z + 1) / (z - 1)

#eval T (ofReal 10000)           -- ≈ 2 (the limit as z → ∞: a/c = 2)
#eval abs (T (ofReal 1.0001))    -- a huge number (we're near z = d/c = 1)
```

## 3.4 — Formal sketch

Mathlib has `OnePoint ℂ` — the one-point compactification of $\mathbb{C}$
— as the Riemann sphere's topological model.

```lean
-- The Riemann sphere as a topological space:
example : Type := OnePoint ℂ

-- It's compact and Hausdorff:
example : CompactSpace (OnePoint ℂ) := inferInstance
```

## 3.5 — Play: where does $\infty$ go?

Try different $(a, b, c, d)$ and see where the special points map.
Replace the literals below and re-run:

```lean
def myT (a b c d z : ComplexF) : ComplexF := (a * z + b) / (c * z + d)

-- T(z) = (3z + 5) / (z + 2): T(∞) = 3, T(-2) = ∞
#eval myT 3 5 1 2 (ofReal 1e6)         -- close to 3 + 0i
#eval abs (myT 3 5 1 2 (ofReal (-1.99999)))  -- huge
```

## 3.6 — Prove it yourself

1. (Easy) Show that the unit circle $|z| = 1$ corresponds under
   stereographic projection to the equator of the sphere.
2. (Medium) Verify that $z \mapsto 1/\bar z$ is the *reflection* of
   the sphere across the equator.  Combine inversion with conjugation
   and watch the imaginary part flip back.
3. (Hard) Show that *every* Möbius transformation extends
   continuously to a self-map of $\hat{\mathbb{C}}$.

## 3.7 — Frontier link

The "no centre, no infinity" character of the sphere is the geometric
intuition behind **renormalisation** in physics: a scale at which
"infinity" looks like nothing special is the scale at which the
theory makes sense.  In ML, the spherical perspective resurfaces in
**spherical CNNs** (rotation-equivariant on $S^2$).

## What's next

Chapter 4 will use the sphere's "closed loops" to give a properly
geometric account of contour integration.
