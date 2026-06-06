# Chapter 3 — Integrals

## 3.1 — The Riemann picture

The integral $\int_a^b f$ is the limit of sums of skinny-rectangle
areas as the rectangles get skinnier.  Three flavours of skinny
rectangle agree in the limit, but disagree by very different amounts
at any finite $n$:

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 360 220" width="360" height="220">
  <!-- f(x) = x²/30 - 1, scaled to fit; just a smooth bump for illustration -->
  <line x1="20" y1="200" x2="350" y2="200" stroke="#333"/>
  <line x1="40" y1="210" x2="40"  y2="20"  stroke="#333"/>

  <!-- 6 left rectangles -->
  <g fill="#cce5ff" stroke="#3399ff">
    <rect x="40"  y="180" width="40" height="20"/>
    <rect x="80"  y="160" width="40" height="40"/>
    <rect x="120" y="130" width="40" height="70"/>
    <rect x="160" y="100" width="40" height="100"/>
    <rect x="200" y="70"  width="40" height="130"/>
    <rect x="240" y="50"  width="40" height="150"/>
  </g>

  <!-- curve -->
  <path d="M40 200 C 100 180, 180 110, 290 30" stroke="#cc0000" fill="none" stroke-width="2"/>

  <text x="170" y="218" font-size="11">left Riemann sum (n = 6)</text>
  <text x="295" y="40"  font-size="11" fill="#cc0000">f(x)</text>
</svg>
```

Left sum *underestimates* an increasing function; right sum
*overestimates* it; midpoint and trapezoid split the error.

## 3.2 — Quadrature on $\int_0^1 x^2\,dx = 1/3$

```lean
def f (x : Float) : Float := x * x

def leftSum (a b : Float) (n : Nat) : Float :=
  let h := (b - a) / Float.ofNat n
  let xs := (List.range n).toArray.map (fun i => a + Float.ofNat i * h)
  h * xs.foldl (fun acc x => acc + f x) 0.0

def rightSum (a b : Float) (n : Nat) : Float :=
  let h := (b - a) / Float.ofNat n
  let xs := (List.range n).toArray.map (fun i => a + Float.ofNat (i + 1) * h)
  h * xs.foldl (fun acc x => acc + f x) 0.0

def midSum (a b : Float) (n : Nat) : Float :=
  let h := (b - a) / Float.ofNat n
  let xs := (List.range n).toArray.map (fun i => a + (Float.ofNat i + 0.5) * h)
  h * xs.foldl (fun acc x => acc + f x) 0.0

def trapSum (a b : Float) (n : Nat) : Float :=
  (leftSum a b n + rightSum a b n) / 2.0

#eval leftSum  0.0 1.0 10
#eval rightSum 0.0 1.0 10
#eval midSum   0.0 1.0 10
#eval trapSum  0.0 1.0 10
#eval midSum   0.0 1.0 100
```

Expected:

```output
0.285000
0.385000
0.332500
0.335000
0.333325
```

A few things to read off:

- left + right straddle the true value $1/3$.
- midpoint already beats trapezoid at the same $n$.
- midpoint at $n = 100$ is within $10^{-5}$.  $O(h^2)$ in action.

## 3.3 — Fundamental Theorem of Calculus, numerically

The FTC says: if $F$ is an antiderivative of $f$, then

$$
\int_a^b f(x)\,dx = F(b) - F(a).
$$

For $f(x) = x^2$, take $F(x) = x^3/3$:

```lean
def F (x : Float) : Float := x*x*x / 3.0
#eval F 1.0 - F 0.0      -- 0.333333
```

Expected:

```output
0.333333
```

— same six digits as the high-$n$ midpoint sum, but for free.  Every
quadrature rule in §3.2 is *approximating* this difference.

## 3.4 — A harder integral: $\int_0^\pi \sin x\,dx = 2$

```lean
def pi : Float := Float.acos (-1.0)
def g (x : Float) : Float := Float.sin x

def midSumG (a b : Float) (n : Nat) : Float :=
  let h := (b - a) / Float.ofNat n
  let xs := (List.range n).toArray.map (fun i => a + (Float.ofNat i + 0.5) * h)
  h * xs.foldl (fun acc x => acc + g x) 0.0

#eval midSumG 0.0 pi 100      -- ≈ 2.000082
```

Expected:

```output
2.000082
```

The exact answer is 2.  The 8×10⁻⁵ error at $n = 100$ scales like
$h^2 = (\pi/100)^2 \approx 10^{-3}$, times the curvature of $\sin$ — a
sanity check you can run in your head.

## 3.5 — The formal statement

```lean
import Mathlib.MeasureTheory.Integral.IntervalIntegral.Basic
import Mathlib.MeasureTheory.Integral.IntervalIntegral.FundThmCalculus
import Mathlib.Analysis.SpecialFunctions.Integrals.Basic
import Mathlib.Analysis.SpecialFunctions.Trigonometric.Basic

open scoped Topology
open MeasureTheory intervalIntegral

-- ∫₀¹ x² dx = 1/3 — closed form via the fundamental theorem.
example : ∫ x in (0:ℝ)..1, x^2 = 1/3 := by
  -- `integral_pow` packages ∫ x^n = (b^(n+1) - a^(n+1))/(n+1).
  simp [integral_pow]

-- ∫₀^π sin x dx = 2.
example : ∫ x in (0:ℝ)..Real.pi, Real.sin x = 2 := by
  simp [integral_sin]

-- Fundamental theorem of calculus: integration is the inverse of
-- differentiation.  `intervalIntegral.integral_eq_sub_of_hasDerivAt`
-- delivers the F(b) - F(a) form.
example {f F : ℝ → ℝ} {a b : ℝ} (hab : a ≤ b)
    (hF : ∀ x ∈ Set.Icc a b, HasDerivAt F (f x) x)
    (hf : IntervalIntegrable f MeasureTheory.volume a b) :
    ∫ x in a..b, f x = F b - F a :=
  integral_eq_sub_of_hasDerivAt (fun x hx => hF x hx) hf
```

The `F b - F a` on the right is the closed-form answer the numerical
midpoint sum in §§3.2–3.4 is groping toward.

That closes the foundations.  In Ch04 we'll move to *sequences and
series* — pointwise vs uniform convergence and the Weierstrass
M-test, again with a picture-first treatment.
