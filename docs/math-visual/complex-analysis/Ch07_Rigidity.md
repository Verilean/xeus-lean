# Chapter 7 — Rigidity: Why Holomorphic Functions Are Determined Almost Everywhere

A real-differentiable function can be wild.  A complex-differentiable
function, on the other hand, is automatically:

- **infinitely differentiable**,
- **analytic** (locally equal to its Taylor series),
- **determined by its values on any non-discrete subset** (identity
  theorem),
- **bounded by its boundary values** (maximum modulus),
- and several other "you can't slip anything past us" properties.

All from Cauchy's integral formula.

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

def PI : Float := 3.141592653589793
```

## 7.1 — Cauchy's integral formula

For $f$ holomorphic on a disk and $z_0$ in the interior, with a
circular contour $\gamma$ of radius $r$ around $z_0$:

$$
f(z_0) = \frac{1}{2\pi i} \oint_\gamma \frac{f(z)}{z - z_0}\,dz.
$$

The value at $z_0$ is the **average** of $f$ around the boundary.

## 7.2 — The derivative is also an integral

$$
f'(z_0) = \frac{1}{2\pi i} \oint_\gamma \frac{f(z)}{(z - z_0)^2}\,dz.
$$

So $f^{(n)}$ exists for every $n$, just from the fact that $f$ is
differentiable once.

Numerical check: $f'(0)$ for $f(z) = e^z$ via the integral formula.
Expected: $e^0 = 1$.

```lean
def cauchyDerivative : ComplexF := Id.run do
  let N : Nat := 500
  let r : Float := 0.5
  let dt : Float := 2.0 * PI / Float.ofNat N
  let mut acc : ComplexF := 0
  for k in [:N] do
    let t : Float := Float.ofNat k * dt
    let z : ComplexF := ofReal r * (ofReal t * I).exp
    let γ' : ComplexF := I * z                 -- (re^{it})' = ire^{it}
    let integrand : ComplexF := z.exp / (z * z)
    acc := acc + integrand * γ' * ofReal dt
  pure (acc / (ofReal (2.0 * PI) * I))

#eval cauchyDerivative
-- Should land near (1.0, 0): f'(0) = e^0 = 1.  ✓
```

## 7.3 — Liouville's theorem

A **bounded entire function is constant**.

Sketch: by Cauchy's derivative formula, $|f'(z_0)| \le M/r$ on a
disk of radius $r$ where $|f| \le M$.  Let $r \to \infty$.  Then
$f' \equiv 0$, so $f$ is constant.

Not true for real functions ($\sin x$ is bounded and non-constant).
The difference: real "entire" allows oscillation; complex entire
does not.

**Application — Fundamental theorem of algebra**: a non-constant
polynomial without zeros would make $1/p$ entire and bounded, hence
constant — contradiction.  So every polynomial has a root.

```lean
-- |1/(z²+1)| is small on a large circle: justifies "1/p is bounded
-- at infinity" for the FTA proof.
def maxInverseAbs (R : Float) : Float := Id.run do
  let N : Nat := 720
  let dt : Float := 2.0 * PI / Float.ofNat N
  let mut m : Float := 0
  for k in [:N] do
    let t : Float := Float.ofNat k * dt
    let z : ComplexF := ofReal R * (ofReal t * I).exp
    let v : Float := abs (1 / (z * z + 1))
    if v > m then m := v
  pure m

#eval maxInverseAbs 10.0       -- tiny: 1/|z²+1| ≤ 1/99 on |z|=10
#eval maxInverseAbs 100.0      -- even tinier
```

## 7.4 — The identity theorem

Two holomorphic functions agreeing on a set with an accumulation
point agree everywhere on the connected region.

Real-smooth has no analogue: $e^{-1/x^2}$ (extended to be $0$ at
$0$) is $C^\infty$, has all derivatives zero at the origin, but
isn't identically zero.

## 7.5 — Maximum modulus principle

For $f$ holomorphic and non-constant on a domain $\Omega$, $|f|$
attains its sup on the boundary, never in the interior.

```lean
def maxOnBoundary (f : ComplexF → ComplexF) (R : Float) (N : Nat) : Float := Id.run do
  let dt : Float := 2.0 * PI / Float.ofNat N
  let mut m : Float := 0
  for k in [:N] do
    let t : Float := Float.ofNat k * dt
    let z : ComplexF := ofReal R * (ofReal t * I).exp
    let v : Float := abs (f z)
    if v > m then m := v
  pure m

def maxInDisk (f : ComplexF → ComplexF) (R : Float) (N : Nat) : Float := Id.run do
  let mut m : Float := 0
  for i in [:N] do
    for j in [:N] do
      let x : Float := -R + 2.0 * R * Float.ofNat i / Float.ofNat N
      let y : Float := -R + 2.0 * R * Float.ofNat j / Float.ofNat N
      if x*x + y*y ≤ R*R then
        let v : Float := abs (f ⟨x, y⟩)
        if v > m then m := v
  pure m

#eval maxOnBoundary (fun z => z * z * z - 2 * z + 1) 1.5 720
#eval maxInDisk     (fun z => z * z * z - 2 * z + 1) 1.5 50
-- Boundary max and interior max should agree.
```

## 7.6 — Formal sketch

```text
%load mathlib
```

```lean
example : True := by
  -- #findDecl "MaximumModulus" 0 10
  -- #findDecl "Liouville" 0 10
  -- #findDecl "AnalyticOn" "eq" 0 20
  trivial
```

## 7.7 — Prove it yourself

1. Prove Liouville from $|f^{(n)}(z_0)| \le n! M / r^n$ with $n = 1$
   and $r \to \infty$.
2. If $f$ is entire and $f(1/n) = 0$ for every positive integer $n$,
   show $f \equiv 0$.  (Identity theorem.)
3. (Hard) A bounded harmonic function on $\mathbb{R}^2$ is constant.
   (Hint: real harmonic = real part of holomorphic.)

## 7.8 — Frontier link

- **Hartogs phenomenon** in several complex variables.
- **Bombieri–Lang conjecture** in arithmetic geometry.
- **Christoffel–Darboux** in ML kernel methods.

## What's next

Chapter 8 uses rigidity to prove the Riemann mapping theorem: every
simply-connected proper subset of $\mathbb{C}$ is biholomorphic to
the unit disk.
