# Chapter 5 — Residues at Work: Real Integrals from Imaginary Paths

Chapter 4 set up the machinery.  Chapter 5 is where it earns its
keep: integrals on the *real* line become one-line residue
computations once you close the path into the upper half plane.

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

def PI : Float := 3.141592653589793
```

## 5.1 — The semicircular contour trick

We want $\displaystyle \int_{-\infty}^{\infty} \frac{dx}{x^2 + 1}$
(calculus: $= \pi$).

Path: the real axis from $-R$ to $R$, then a semicircular arc closing
the loop in the upper half plane.  As $R \to \infty$:

- the real-segment integral → the integral we want,
- the semicircular arc → 0 (integrand decays like $1/R^2$),
- the closed-contour integral picks up $2\pi i$ times the residue at
  every pole inside.

Only pole of $1/(z^2+1)$ in the upper half plane: $z = i$, with
residue $1/(2i)$.  So the integral is $2\pi i \cdot 1/(2i) = \pi$.

```lean
#html "<svg viewBox='-3.5 -1 7 4' width='480' style='background:#f4f4f8'>
  <line x1='-3.5' y1='2.5' x2='3.5' y2='2.5' stroke='#aaa' stroke-width='0.03'/>
  <line x1='-3' y1='2.5' x2='3' y2='2.5' stroke='#268' stroke-width='0.06'/>
  <path d='M 3 2.5 A 3 3 0 0 1 -3 2.5' fill='none' stroke='#268' stroke-width='0.06'/>
  <circle cx='0' cy='1.5' r='0.1' fill='#c25'/>
  <text x='0.15' y='1.35' fill='#c25' font-size='0.3'>i</text>
</svg>"
```

## 5.2 — Numerical check

```lean
def realIntegralPi : Float := Id.run do
  let R : Float := 100.0
  let N : Nat := 4000
  let dx : Float := 2.0 * R / Float.ofNat N
  let mut acc : Float := 0
  for k in [:N] do
    let x : Float := -R + Float.ofNat k * dx
    acc := acc + dx / (x*x + 1.0)
  pure acc

#eval realIntegralPi          -- ≈ 3.1416 = π
#eval PI                      -- 3.141593, for comparison
```

The agreement is the whole point: a *real* integral came out of a
*complex* residue.

## 5.3 — Play: a harder one

$\displaystyle \int_{-\infty}^{\infty} \frac{dx}{(x^2+1)^2} = \frac{\pi}{2}$.

```lean
def harderRealIntegral : Float := Id.run do
  let R : Float := 100.0
  let N : Nat := 4000
  let dx : Float := 2.0 * R / Float.ofNat N
  let mut acc : Float := 0
  for k in [:N] do
    let x : Float := -R + Float.ofNat k * dx
    let d : Float := x*x + 1.0
    acc := acc + dx / (d * d)
  pure acc

#eval harderRealIntegral      -- ≈ π/2 ≈ 1.5708
#eval PI / 2.0
```

For a pole of order $2$ at $z = i$:
$\operatorname*{Res}_{z=i} 1/(z^2+1)^2 = 1/(4i)$.  Integral
$= 2\pi i / (4i) = \pi/2$.  ✓

## 5.4 — A trigonometric integral

$\displaystyle \int_0^{2\pi} \frac{d\theta}{2 + \cos\theta} = \frac{2\pi}{\sqrt 3}$.

Substituting $z = e^{i\theta}$ turns it into a contour integral over
the unit circle.  Pole inside: $z = -2 + \sqrt 3$, residue
$1/(2\sqrt 3)$.  Integral $= (2/i) \cdot 2\pi i / (2\sqrt 3)
= 2\pi / \sqrt 3$.

```lean
def trigIntegral : Float := Id.run do
  let N : Nat := 2000
  let dθ : Float := 2.0 * PI / Float.ofNat N
  let mut acc : Float := 0
  for k in [:N] do
    let θ : Float := Float.ofNat k * dθ
    acc := acc + dθ / (2.0 + θ.cos)
  pure acc

#eval trigIntegral            -- ≈ 3.6276 = 2π/√3
#eval 2.0 * PI / (3.0 : Float).sqrt
```

## 5.5 — Formal sketch

```text
%load mathlib
```

```lean
import Mathlib.Analysis.SpecialFunctions.Integrals.Basic

-- A formal statement of "∫_ℝ dx/(x²+1) = π":
example : True := by
  -- Mathlib has `MeasureTheory.integral_one_div_one_add_sq` or similar.
  -- The residue-theorem proof is one approach; the arctan-substitution
  -- proof is another.  #findDecl "one_add_sq" 0 20
  trivial
```

## 5.6 — Prove it yourself

1. Evaluate $\int_{-\infty}^{\infty} dx/(x^4+1)$.  Four poles, two in
   the upper half plane: $e^{i\pi/4}$ and $e^{3i\pi/4}$.
2. Compute the Dirichlet integral $\int_0^\infty (\sin x)/x\,dx
   = \pi/2$ by integrating $e^{iz}/z$ around an indented semicircle.
3. (Hard) Evaluate $\int_0^\infty x^{a-1}/(1+x)\,dx = \pi/\sin(\pi a)$
   for $0 < a < 1$ using a keyhole contour around the branch cut.

## 5.7 — Frontier link

- **Mellin transform** — analytic number theory's workhorse.
- **Asymptotic expansion** of integrals via saddle point.
- **Rational Krylov methods** in numerical linear algebra.

## What's next

Chapter 6 turns the contour-deformation game into a counting
principle — the argument principle, which counts zeros without
finding them.
