# Chapter 7 — Rigidity: Why Holomorphic Functions Are Determined Almost Everywhere

A real-differentiable function can be a wild thing.  It can be
differentiable once but not twice.  It can match a polynomial on a
huge set and disagree everywhere else.  It can have a derivative that
is itself discontinuous.

Complex-differentiable functions are nothing like this.  Once a
function is differentiable at every point of an open set, it's
automatically:

- **infinitely differentiable** (smooth),
- **analytic** (locally equal to its Taylor series),
- **determined by its values on any non-discrete subset** (identity
  theorem),
- **bounded by its boundary values** in a region (maximum modulus),
- and several other "you can't slip anything past us" properties.

This chapter is a tour of why.  The key is Cauchy's integral
formula, which writes $f(z_0)$ as an integral of $f$ over any
surrounding contour.

```lean
%load mathlib
```

```lean
import Mathlib.Analysis.Complex.Basic
open Complex Real
```

## 7.1 — Cauchy's integral formula

For $f$ holomorphic on a disk and $z_0$ in the interior, with a
circular contour $\gamma$ of radius $r$ around $z_0$:

$$
f(z_0) = \frac{1}{2\pi i} \oint_\gamma \frac{f(z)}{z - z_0}\,dz.
$$

The value at the centre is the **average** of $f$ around the boundary
(with the $z - z_0$ weighting baked into the contour integral).

Picture:

```lean
#html "<svg viewBox='-2 -2 4 4' width='400' style='background:#f4f4f8'>
  <circle cx='0' cy='0' r='1.5' fill='none' stroke='#268' stroke-width='0.04'/>
  <circle cx='0' cy='0' r='0.08' fill='#c25'/>
  <text x='0.15' y='-0.05' fill='#c25' font-size='0.22'>z₀</text>
  <text x='-1.45' y='-0.05' fill='#268' font-size='0.22'>γ</text>
  <text x='-1.8' y='1.9' fill='#444' font-size='0.22'>f(z₀) = ⟨f over γ⟩</text>
</svg>"
```

## 7.2 — The derivative is also an integral

Differentiate under the integral sign:

$$
f'(z_0) = \frac{1}{2\pi i} \oint_\gamma \frac{f(z)}{(z - z_0)^2}\,dz.
$$

And in general:

$$
f^{(n)}(z_0) = \frac{n!}{2\pi i} \oint_\gamma \frac{f(z)}{(z - z_0)^{n+1}}\,dz.
$$

This is "Cauchy's differentiation formula", and it has one
extraordinary consequence: **$f^{(n)}$ exists for every $n$, just
from the fact that $f$ is differentiable once**.  Real-analytic
functions inherit this property because they are analytic, but for
*holomorphic* functions it's automatic from a single derivative.

Numerical sanity check: estimate $f'(0)$ for $f(z) = e^z$ via the
integral formula.

```lean
def cauchyDerivative : ℂ := Id.run do
  let N := 1000
  let r : ℝ := 0.5
  let dt : ℝ := 2 * Real.pi / (N : ℝ)
  let mut acc : ℂ := 0
  for k in [:N] do
    let t : ℝ := (k : ℝ) * dt
    let z : ℂ := r * Complex.exp (t * I)
    let γ' : ℂ := I * z      -- (re^{it})' = ire^{it}
    -- integrand of (2πi)^{-1} ∮ e^z / z² dz
    let integrand : ℂ := Complex.exp z / (z * z)
    acc := acc + integrand * γ' * dt
  pure (acc / (2 * Real.pi * I))

#eval cauchyDerivative
-- Should land near 1 + 0i — the derivative of e^z at 0 is e^0 = 1. ✓
```

## 7.3 — Liouville's theorem (and a consequence)

A **bounded entire function is constant**.  An "entire" function is
one that's holomorphic on all of $\mathbb{C}$.

Proof sketch from Cauchy's derivative formula: $|f'(z_0)| \le M/r$
where $M$ is the bound on $|f|$ and $r$ is the contour radius.  Let
$r \to \infty$.  Then $|f'(z_0)| = 0$ everywhere, so $f$ is constant.

This is *not true* for real functions — $\sin x$ is bounded and
non-constant.  The difference is exactly that real "entire" allows
oscillation; complex entire does not.

**Application: the fundamental theorem of algebra (Liouville's
proof).**  Suppose a non-constant polynomial $p(z)$ has no zero.
Then $1/p(z)$ is entire (no division-by-zero) and bounded (because
$|p(z)| \to \infty$ as $|z| \to \infty$).  By Liouville it's
constant, so $p$ is constant — contradiction.  Hence every
non-constant polynomial has at least one zero.

```lean
-- Numerical: |1/p(z)| ≤ some_bound on, say, |z| ≥ 10 for p(z) = z² + 1.
def maxInverseAbs (R : ℝ) : ℝ := Id.run do
  let N := 720
  let dt : ℝ := 2 * Real.pi / (N : ℝ)
  let mut m : ℝ := 0
  for k in [:N] do
    let t : ℝ := (k : ℝ) * dt
    let z : ℂ := R * Complex.exp (t * I)
    let v : ℝ := Complex.abs (1 / (z * z + 1))
    if v > m then m := v
  pure m

#eval maxInverseAbs 10.0
-- Tiny number: 1/|z²+1| ≤ 1/99 on |z|=10.
#eval maxInverseAbs 100.0
-- Even tinier.
```

## 7.4 — The identity theorem

If two holomorphic functions agree on a set with an accumulation
point (e.g. on a small interval, or on a sequence converging to
some point), they agree **everywhere on the connected region**.

Sketch: the difference $g = f_1 - f_2$ is holomorphic and zero on a
set with an accumulation point.  Expand $g$ as a Taylor series at
that point: every coefficient must be zero (otherwise the zero set
would be isolated, contradicting accumulation).  So $g$ is zero in a
neighbourhood, and by analytic continuation (pasting Taylor disks)
zero on the whole connected component.

Compare with real:  define $f(x) = e^{-1/x^2}$ for $x \neq 0$ and
$f(0) = 0$.  It's $C^\infty$, all derivatives are zero at the
origin, but $f$ is not the zero function.  No accumulation-point
identity theorem in the real-smooth world.  Holomorphic is strictly
stricter than $C^\infty$.

## 7.5 — Maximum modulus principle

For $f$ holomorphic and non-constant on a domain $\Omega$, $|f|$
attains its supremum on the boundary, never in the interior.

A clean statement: if $|f(z_0)| \ge |f(z)|$ for all $z$ in a
neighbourhood of $z_0$, then $f$ is constant.

Geometric intuition: by Cauchy's integral formula, $f(z_0)$ is an
average of $f$ on a circle around $z_0$.  If $f(z_0)$ were a
strict maximum of $|f|$, the average couldn't possibly equal that
maximum unless every neighbouring value also equalled it — at which
point you've spread the "maximum" to a whole neighbourhood, and
analytic continuation does the rest.

```lean
-- Numerical: sample |f(z)| inside a disk for a non-constant holomorphic
-- f, observe that the boundary supremum dominates everywhere inside.
def maxOnBoundary (f : ℂ → ℂ) (R : ℝ) (N : Nat) : ℝ := Id.run do
  let dt : ℝ := 2 * Real.pi / (N : ℝ)
  let mut m : ℝ := 0
  for k in [:N] do
    let t : ℝ := (k : ℝ) * dt
    let z : ℂ := R * Complex.exp (t * I)
    let v : ℝ := Complex.abs (f z)
    if v > m then m := v
  pure m

def maxInDisk (f : ℂ → ℂ) (R : ℝ) (N : Nat) : ℝ := Id.run do
  let mut m : ℝ := 0
  -- crude grid sampling
  for i in [:N] do
    for j in [:N] do
      let x : ℝ := -R + 2 * R * (i : ℝ) / (N : ℝ)
      let y : ℝ := -R + 2 * R * (j : ℝ) / (N : ℝ)
      if x*x + y*y ≤ R*R then
        let v : ℝ := Complex.abs (f (⟨x, y⟩))
        if v > m then m := v
  pure m

#eval (maxOnBoundary (fun z => z^3 - 2*z + 1) 1.5 720,
       maxInDisk     (fun z => z^3 - 2*z + 1) 1.5 100)
-- Boundary maximum and interior maximum agree (up to grid resolution).
```

## 7.6 — Formal sketch

Mathlib has all of this in `Mathlib.Analysis.Complex.*`:

```lean
-- The maximum modulus principle:
#findDecl "MaximumModulus" 0 10

-- Liouville's theorem:
#findDecl "Liouville" 0 10

-- The identity theorem:
#findDecl "AnalyticOn" "eq" 0 20
```

Each is a few-line invocation given the right hypotheses.

## 7.7 — Prove it yourself

1. (Easy) Prove Liouville's theorem from the Cauchy estimate
   $|f^{(n)}(z_0)| \le n! M / r^n$, by letting $r \to \infty$ with
   $n = 1$.
2. (Medium) Use the identity theorem to show: if $f$ is entire and
   $f(1/n) = 0$ for every positive integer $n$, then $f$ is the zero
   function.  (Hint: $1/n \to 0$ is an accumulation.)
3. (Hard) Show that a bounded harmonic function on $\mathbb{R}^2$ is
   constant.  (Hint: a real harmonic function is the real part of a
   holomorphic function; apply Liouville.)

## 7.8 — Frontier link

- The **Hartogs phenomenon** in several complex variables takes
  rigidity further: in $\mathbb{C}^n$ with $n \ge 2$, a holomorphic
  function defined on a region with a "punched-out" interior
  automatically extends to the whole region.  No analogue in $n=1$.
  This is the start of complex geometry's distinctive flavour.
- **Bombieri–Lang conjecture** in arithmetic geometry uses rigidity
  of holomorphic maps between complex algebraic varieties — the
  generic point of view that "non-constant maps are rare and
  geometric."
- In **ML theory**, the rigidity of holomorphic functions resurfaces
  in the **Christoffel–Darboux** identity for orthogonal polynomials
  and the **resolvent** picture of kernel methods: the spectrum of
  an operator is determined by its action on any holomorphic test
  function.

## What's next

Chapter 8 will use these rigidity properties to prove the **Riemann
mapping theorem**: every simply-connected proper subset of
$\mathbb{C}$ is biholomorphic to the unit disk.  That single result
is the geometric heart of conformal field theory and a non-trivial
chunk of 19th-century mathematics in one statement.
