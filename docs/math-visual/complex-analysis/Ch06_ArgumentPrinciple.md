# Chapter 6 — The Argument Principle: Counting Zeros Without Finding Them

Suppose you have a complicated analytic function $f$ and you want to
know: how many zeros does $f$ have inside this disk?

For polynomials you can in principle find them numerically.  For
something like $f(z) = e^z + z^{100} - 1$ on $|z| < 5$, you can't.

The argument principle says: walk a closed loop around the region,
watch the *argument* of $f$ rotate, and divide the total rotation by
$2\pi$.  That counts the zeros (minus the poles, counted with
multiplicity).  You never need to know *where* the zeros are.

```lean
%load mathlib
```

```lean
import Mathlib.Analysis.Complex.Basic
import Mathlib.Analysis.SpecialFunctions.Complex.Log
open Complex Real
```

## 6.1 — The picture

Pick a closed contour $\gamma$ enclosing a region $\Omega$, and a
function $f$ that's meromorphic on $\Omega$ with no zeros or poles on
$\gamma$ itself.  As $z$ traces $\gamma$ once, the image $f(z)$
traces some closed curve in the $w$-plane.

The number of times $f(z)$ winds around the origin equals the number
of zeros of $f$ inside $\gamma$ minus the number of poles, both
counted with multiplicity:

$$
\frac{1}{2\pi i} \oint_\gamma \frac{f'(z)}{f(z)}\,dz = N - P.
$$

The integrand $f'/f$ is the *logarithmic derivative* of $f$; its
integral measures change in $\log f$, hence change in $\arg f$
modulo $2\pi$.

```lean
#html "<svg viewBox='-2 -1.5 8 3.5' width='540' style='background:#f4f4f8'>
  <text x='0' y='-1.0' fill='#444' font-size='0.3'>z-plane</text>
  <circle cx='1' cy='1' r='1.3' fill='none' stroke='#268' stroke-width='0.05'/>
  <circle cx='0.7' cy='0.6' r='0.08' fill='#c25'/>
  <circle cx='1.4' cy='1.4' r='0.08' fill='#c25'/>
  <text x='-1.5' y='2.4' fill='#268' font-size='0.25'>γ (the contour)</text>
  <text x='0.9' y='0.45' fill='#c25' font-size='0.2'>zeros of f</text>
  <line x1='3.0' y1='1.0' x2='3.6' y2='1.0' stroke='#888' stroke-width='0.04' marker-end='url(#a)'/>
  <defs><marker id='a' viewBox='0 0 10 10' refX='5' refY='5' markerWidth='4' markerHeight='4' orient='auto'>
    <path d='M0,0 L10,5 L0,10 z' fill='#888'/>
  </marker></defs>
  <text x='4' y='-1.0' fill='#444' font-size='0.3'>w = f(z) plane</text>
  <circle cx='4.8' cy='1' r='0.08' fill='#000'/>
  <path d='M 5 0.5 Q 6.5 -0.5 7.2 1 Q 6.5 2.5 5 2 Q 4 1.7 4.5 0.2 Q 5.4 -0.3 5.8 0.4 Q 6 1 5.5 1.3 Q 4.8 1.4 5 0.5'
        fill='none' stroke='#268' stroke-width='0.05'/>
  <text x='4.6' y='1.05' fill='#000' font-size='0.2'>0</text>
  <text x='4' y='2.6' fill='#268' font-size='0.25'>f(γ), winding twice</text>
</svg>"
```

If you literally watch the curve $f(\gamma)$ as $z$ traces $\gamma$,
count how many times it loops around the origin — that's $N - P$.

## 6.2 — Smallest example: $f(z) = z^n$

For $f(z) = z^n$ on the unit circle, $f(e^{it}) = e^{int}$ traces
the unit circle in the $w$-plane $n$ times.  Winding number: $n$.
Zeros of $z^n$ inside the unit disk: $n$ (a single zero at $z = 0$
of multiplicity $n$).  ✓

```lean
-- Numerical demonstration: walk z around the unit circle, track the
-- argument of f(z) = z^3.
def windingZ3 : Int := Id.run do
  let N := 360
  let dt : ℝ := 2 * Real.pi / (N : ℝ)
  let mut total : ℝ := 0
  let mut prev : ℝ := 0
  for k in [:N + 1] do
    let t : ℝ := (k : ℝ) * dt
    let z : ℂ := Complex.exp (t * I)
    let w : ℂ := z * z * z
    -- arg in (-π, π]
    let θ : ℝ := Real.atan2 w.im w.re
    if k > 0 then
      let dθ := θ - prev
      -- unwrap: snap jumps of ~2π
      let adj : ℝ :=
        if dθ > Real.pi then dθ - 2 * Real.pi
        else if dθ < -Real.pi then dθ + 2 * Real.pi
        else dθ
      total := total + adj
    prev := θ
  pure (Int.ofNat (Float.toUInt32 (Float.ofScientific (total.toFloat / (2 * 3.14159265358979).toFloat
            |>.abs.toUInt64.toNat) false 0)).toNat)

-- (The Int conversion is awkward; the point is the floating-point
-- total / (2π) is the winding number.)
#eval (Id.run do
  let N := 360
  let dt : ℝ := 2 * Real.pi / (N : ℝ)
  let mut total : ℝ := 0
  let mut prev : ℝ := 0
  for k in [:N + 1] do
    let t : ℝ := (k : ℝ) * dt
    let z : ℂ := Complex.exp (t * I)
    let w : ℂ := z * z * z
    let θ : ℝ := Real.atan2 w.im w.re
    if k > 0 then
      let dθ := θ - prev
      let adj : ℝ :=
        if dθ > Real.pi then dθ - 2 * Real.pi
        else if dθ < -Real.pi then dθ + 2 * Real.pi
        else dθ
      total := total + adj
    prev := θ
  pure (total / (2 * Real.pi)))
-- Should print ≈ 3.0.  Switch to z*z*z*z and it should give 4.
```

## 6.3 — Rouché's theorem: comparing two functions on a contour

The most common practical use of the argument principle is **Rouché's
theorem**:

> If $|f(z) - g(z)| < |f(z)|$ on a closed contour $\gamma$, then $f$
> and $g$ have the same number of zeros inside $\gamma$.

In words: if you can dominate the difference by the larger of the
two functions on the boundary, the count is the same.

Example: $f(z) = z^5 + 10z + 1$.  On the circle $|z| = 2$,
$|z^5| = 32$ dominates $|10z + 1| \le 21$.  So $z^5$ and the full
polynomial have the same number of zeros inside $|z| = 2$: **five**.
The polynomial has five roots.  We didn't have to find them.

```lean
-- Verify dominance numerically on the contour |z| = 2.
def rouchePolynomial : List (ℝ × ℝ) := Id.run do
  let N := 36  -- one sample every 10°
  let dt : ℝ := 2 * Real.pi / (N : ℝ)
  let mut out : List (ℝ × ℝ) := []
  for k in [:N] do
    let t : ℝ := (k : ℝ) * dt
    let z : ℂ := 2 * Complex.exp (t * I)
    let dom : ℝ := Complex.abs (z ^ 5)            -- |z^5| on circle = 32
    let diff : ℝ := Complex.abs (10 * z + 1)
    out := out.concat (dom, diff)
  pure out

#eval rouchePolynomial
-- Every row should show "dom (≈ 32) > diff (≤ 21)".
```

## 6.4 — Counting roots of transcendentals

Now the same machinery on $f(z) = e^z + z$:

- On the imaginary axis $z = iy$: $f(iy) = e^{iy} + iy$ stays on a
  curve that doesn't pass through $0$ (you can verify).
- On a large semicircle in the right half plane, $|e^z|$ dominates
  $|z|$, so $f$ winds once for each "$e^z$ winding".
- Hand-wavy conclusion: $f$ has exactly one zero in the right half
  plane.

You won't pin down where it is from this argument.  You'll know it
exists, and you'll know how many.

## 6.5 — Play: try your own polynomial

Pick a polynomial $p(z)$ of your choice.  Pick a contour size $R$.
Walk a fine sampling of $z = R e^{it}$, compute the winding number of
$p(z)$ around 0, and compare to the degree.  When does the winding
number drop below the degree?  (Answer: when not all roots fit inside
$|z| < R$.)

```lean
-- Generic root-counter via numerical winding.
def countZerosInside (p : ℂ → ℂ) (R : ℝ) (N : Nat) : ℝ := Id.run do
  let dt : ℝ := 2 * Real.pi / (N : ℝ)
  let mut total : ℝ := 0
  let mut prev : ℝ := 0
  for k in [:N + 1] do
    let t : ℝ := (k : ℝ) * dt
    let z : ℂ := R * Complex.exp (t * I)
    let w : ℂ := p z
    let θ : ℝ := Real.atan2 w.im w.re
    if k > 0 then
      let dθ := θ - prev
      let adj : ℝ :=
        if dθ > Real.pi then dθ - 2 * Real.pi
        else if dθ < -Real.pi then dθ + 2 * Real.pi
        else dθ
      total := total + adj
    prev := θ
  pure (total / (2 * Real.pi))

-- Roots of z^3 - 1: at 1, e^{2πi/3}, e^{4πi/3} — all on the unit circle.
-- A radius R = 2 should catch all three.
#eval countZerosInside (fun z => z^3 - 1) 2.0 720
-- ≈ 3.0

-- A radius R = 0.5 catches none.
#eval countZerosInside (fun z => z^3 - 1) 0.5 720
-- ≈ 0.0
```

## 6.6 — Formal sketch

Mathlib has `Complex.tsum_logDeriv_eq` and various forms of the
argument principle scattered around `Mathlib.Analysis.Complex.*`.
The cleanest formal statement involves divisors of meromorphic
functions; that's heavier machinery than fits a tutorial chapter.

For the version applicable here:

```lean
-- "If f is holomorphic and nonzero on γ, the winding number of f∘γ
-- around 0 equals the number of zeros of f inside γ (with multiplicity)."
example (γ : ℝ → ℂ) (a b : ℝ) (hγ : ContinuousOn γ (Set.Icc a b))
    (f : ℂ → ℂ) : True := by
  -- Statement TBD — see `Complex.contour_argument_principle`
  -- (or `#findDecl "argument" 0 20` if the name has drifted).
  trivial
```

## 6.7 — Prove it yourself

1. Use the argument principle to show that $p(z) = z^4 + z + 1$ has
   exactly four roots in the disk $|z| < 2$.  (Hint: dominate on the
   circle $|z| = 2$.)
2. Use Rouché's theorem to show that $z^5 - 6z + 3$ has all its
   roots in the annulus $1 < |z| < 2$.
3. (Hard) The fundamental theorem of algebra: every non-constant
   polynomial $p(z)$ of degree $n$ has exactly $n$ complex roots
   (with multiplicity).  Sketch the standard contour-integration
   proof: on a sufficiently large circle $|z| = R$, $p(z)$ is
   dominated by its leading term $z^n$, so by Rouché both have the
   same number of zeros inside, namely $n$.

(Exercise 3 is the cleanest proof of FTA there is.  Every other proof
either reduces to it, or to "$\mathbb{C}$ is algebraically closed via
topology".)

## 6.8 — Frontier link

- **Stability theory** for dynamical systems uses the argument
  principle in the form of the **Nyquist criterion**: walk the unit
  circle, watch the transfer function's image, decide if the system
  is stable from the winding number.  Same picture, control theory's
  bread and butter.
- **Numerical root-finding** (Durand–Kerner, Aberth) seeds with a
  bounding circle from Rouché-style estimates.
- The **Riemann hypothesis** is a statement about the winding number
  of $\zeta$ along the critical line.  Every published failure to
  prove RH stops, eventually, on an argument-principle-shaped
  obstruction.

## What's next

Chapter 7 will use Cauchy's integral formula to derive an extraordinary
fact: **a holomorphic function is automatically infinitely
differentiable**, and a fortiori analytic — i.e., equal to its Taylor
series.  This makes complex analysis startlingly rigid compared to
real analysis, and it's the source of all the rigidity you'll meet
later (Schwarz lemma, Liouville, maximum modulus principle, …).
