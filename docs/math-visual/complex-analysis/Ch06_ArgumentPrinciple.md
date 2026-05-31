# Chapter 6 — The Argument Principle: Counting Zeros Without Finding Them

Suppose you have $f(z) = e^z + z^{100} - 1$ on $|z| < 5$ and want to
know how many zeros are inside.  You can't find them in closed form.
The argument principle says: walk a closed loop around the region,
watch the argument of $f$ rotate, and divide the total rotation by
$2\pi$.  That counts the zeros (minus poles), without ever finding
them.

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
@[inline] def abs (a : ComplexF) : Float := (a.re * a.re + a.im * a.im).sqrt
@[inline] def arg (a : ComplexF) : Float := Float.atan2 a.im a.re
@[inline] def exp (a : ComplexF) : ComplexF :=
  let m := a.re.exp; ⟨m * a.im.cos, m * a.im.sin⟩
def I : ComplexF := ⟨0, 1⟩
def ofReal (r : Float) : ComplexF := ⟨r, 0⟩
instance : Add ComplexF := ⟨add⟩
instance : Sub ComplexF := ⟨sub⟩
instance : Mul ComplexF := ⟨mul⟩
instance : OfNat ComplexF n where ofNat := ⟨Float.ofNat n, 0⟩
end ComplexF
open ComplexF

def PI : Float := 3.141592653589793
```

## 6.1 — The argument principle

For $f$ meromorphic on a region with no zeros or poles on the closed
contour $\gamma$:

$$
\frac{1}{2\pi i} \oint_\gamma \frac{f'(z)}{f(z)}\,dz = N - P
$$

where $N$ is the number of zeros and $P$ the number of poles inside,
both with multiplicity.  As $z$ traces $\gamma$, the image $f(z)$
traces a curve in the $w$-plane; the integer above is exactly the
number of times that image curve winds around the origin.

## 6.2 — Smallest example: $f(z) = z^n$

For $f(z) = z^3$ on the unit circle, $f(e^{it}) = e^{3it}$ winds
around 0 *three* times.  Zeros of $z^3$ inside the unit disk: $3$
(triple zero at origin).  ✓

```lean
-- Walk the unit circle, accumulate Δarg(f(z)), normalise by 2π.
def winding (p : ComplexF → ComplexF) (R : Float) (N : Nat) : Float := Id.run do
  let dt : Float := 2.0 * PI / Float.ofNat N
  let mut total : Float := 0
  let mut prev : Float := 0
  for k in [:N + 1] do
    let t : Float := Float.ofNat k * dt
    let z : ComplexF := ofReal R * (ofReal t * I).exp
    let θ : Float := arg (p z)
    if k > 0 then
      let dθ := θ - prev
      -- unwrap jumps of ~2π
      let adj : Float :=
        if dθ > PI then dθ - 2.0 * PI
        else if dθ < -PI then dθ + 2.0 * PI
        else dθ
      total := total + adj
    prev := θ
  pure (total / (2.0 * PI))

#eval winding (fun z => z * z * z) 1.0 720         -- ≈ 3
#eval winding (fun z => z * z * z * z) 1.0 720     -- ≈ 4
```

## 6.3 — Rouché's theorem

**If $|f(z) - g(z)| < |f(z)|$ on $\gamma$, then $f$ and $g$ have the
same number of zeros inside.**

Example: $f(z) = z^5$ dominates $|10z + 1| \le 21$ on $|z| = 2$,
where $|z^5| = 32$.  So $z^5 + 10z + 1$ has the same number of zeros
inside $|z| = 2$ as $z^5$: **five**.

```lean
def dominanceCheck : List (Float × Float) := Id.run do
  let N : Nat := 12
  let dt : Float := 2.0 * PI / Float.ofNat N
  let mut out : List (Float × Float) := []
  for k in [:N] do
    let t : Float := Float.ofNat k * dt
    let z : ComplexF := ofReal 2.0 * (ofReal t * I).exp
    let dom : Float := abs (z * z * z * z * z)
    let diff : Float := abs (ofReal 10.0 * z + 1)
    out := out.concat (dom, diff)
  pure out

#eval dominanceCheck
-- Every row: dom = 32 (consistently), diff ≤ ~21.  Dominance holds.
```

## 6.4 — Counting roots of any polynomial

```lean
def countZerosInside (p : ComplexF → ComplexF) (R : Float) (N : Nat) : Float :=
  winding p R N

-- Roots of z³ - 1 lie on the unit circle.
#eval countZerosInside (fun z => z * z * z - 1) 2.0 720    -- ≈ 3
#eval countZerosInside (fun z => z * z * z - 1) 0.5 720    -- ≈ 0
```

## 6.5 — Formal sketch

```lean
%load mathlib
```

```lean
example : True := by
  -- The argument principle is named several ways in Mathlib; try
  -- #findDecl "argumentPrinciple" 0 10
  -- and #findDecl "logDeriv" 0 20.
  trivial
```

## 6.6 — Prove it yourself

1. Use Rouché to show $p(z) = z^4 + z + 1$ has all 4 roots in
   $|z| < 2$.
2. Show $z^5 - 6z + 3$ has all roots in the annulus $1 < |z| < 2$.
3. (Hard) Prove the fundamental theorem of algebra by Rouché: on a
   sufficiently large circle, the leading term of $p(z)$ of degree
   $n$ dominates everything else, so $p$ and $z^n$ have the same
   number of zeros inside, namely $n$.

## 6.7 — Frontier link

- **Nyquist criterion** in control theory.
- Seed bounds for **Durand–Kerner / Aberth** root-finders.
- Zero-counting along the critical line is the Riemann hypothesis.

## What's next

Chapter 7 uses Cauchy's integral formula to derive an extraordinary
fact: holomorphic ⟹ infinitely differentiable ⟹ analytic.  Holomorphic
functions are vastly more rigid than real-differentiable ones.
