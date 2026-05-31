# Chapter 5 — Residues at Work: Real Integrals from Imaginary Paths

Chapter 4 set up the machinery.  Chapter 5 is where it earns its
keep: integrals on the *real* line that elementary calculus chokes on
become one-line residue computations once you close the path into
the upper half plane.

```lean
%load mathlib
```

```lean
import Mathlib.Analysis.SpecialFunctions.Complex.Circle
import Mathlib.Analysis.SpecialFunctions.Pow.Complex
open Complex Real
```

## 5.1 — The semicircular contour trick

We want $\displaystyle \int_{-\infty}^{\infty} \frac{dx}{x^2 + 1}$.
Calculus students recognise this as $\arctan x$, which evaluates to
$\pi$.  Let's redo it as a contour integral and see what changes.

Path: the real axis from $-R$ to $R$, then a semicircular arc
$C_R$ of radius $R$ closing the loop in the upper half plane.  As
$R \to \infty$:

- the integral over the real segment becomes the integral we want,
- the integral over $C_R$ vanishes (the integrand decays like
  $1/R^2$, the path length grows like $R$, so the contribution is
  $O(1/R)$),
- the closed-contour integral picks up $2\pi i$ times the residue at
  every pole inside.

The only pole of $1/(z^2+1)$ in the upper half plane is at $z = i$:

$$
\operatorname*{Res}_{z = i} \frac{1}{z^2+1}
= \lim_{z \to i} \frac{z - i}{(z-i)(z+i)}
= \frac{1}{2i}.
$$

So

$$
\int_{-\infty}^{\infty} \frac{dx}{x^2+1}
\;=\; 2\pi i \cdot \frac{1}{2i}
\;=\; \pi.
$$

The picture, for a moment:

```lean
#html "<svg viewBox='-3.5 -1 7 4' width='480' style='background:#f4f4f8'>
  <line x1='-3.5' y1='2.5' x2='3.5' y2='2.5' stroke='#aaa' stroke-width='0.03'/>
  <line x1='0' y1='-1' x2='0' y2='3.5' stroke='#aaa' stroke-width='0.03'/>
  <line x1='-3' y1='2.5' x2='3' y2='2.5' stroke='#268' stroke-width='0.06'/>
  <path d='M 3 2.5 A 3 3 0 0 1 -3 2.5' fill='none' stroke='#268' stroke-width='0.06'/>
  <circle cx='0' cy='1.5' r='0.1' fill='#c25'/>
  <text x='0.15' y='1.35' fill='#c25' font-size='0.3'>i</text>
  <text x='2.7' y='2.85' fill='#268' font-size='0.3'>R</text>
  <text x='-3.3' y='2.85' fill='#268' font-size='0.3'>−R</text>
  <text x='1.0' y='0.4' fill='#268' font-size='0.3'>C_R</text>
</svg>"
```

## 5.2 — Numerical check

```lean
-- Sample the real integral on [-100, 100] with 4000 trapezoids.
def realIntegral : ℝ := Id.run do
  let R : ℝ := 100
  let N := 4000
  let dx := 2 * R / (N : ℝ)
  let mut acc : ℝ := 0
  for k in [:N] do
    let x : ℝ := -R + (k : ℝ) * dx
    acc := acc + dx / (x*x + 1)
  pure acc

#eval realIntegral
-- Should land near 3.1416... = π.

-- Residue prediction: 2π · (1/2) = π.
#eval Real.pi
```

The agreement is the whole point: a calculation about *real* integrals
came out of a calculation about *complex* residues.

## 5.3 — Play: a harder one

Try $\displaystyle \int_{-\infty}^{\infty} \frac{dx}{(x^2+1)^2}$.

```lean
-- Numerical:
def harderRealIntegral : ℝ := Id.run do
  let R : ℝ := 100
  let N := 4000
  let dx := 2 * R / (N : ℝ)
  let mut acc : ℝ := 0
  for k in [:N] do
    let x : ℝ := -R + (k : ℝ) * dx
    let d := x*x + 1
    acc := acc + dx / (d * d)
  pure acc

#eval harderRealIntegral
-- ≈ π/2 = 1.5708
```

Residue analysis: pole of order $2$ at $z = i$.  For a pole of order
$n$ at $z_0$,
$$
\operatorname*{Res}_{z = z_0} f(z) = \frac{1}{(n-1)!} \lim_{z \to z_0}
\frac{d^{n-1}}{dz^{n-1}} \left[ (z - z_0)^n f(z) \right].
$$
For $f(z) = 1/(z^2+1)^2$ at $z = i$, with $n=2$:
$$
\operatorname*{Res}_{z=i} \frac{1}{(z^2+1)^2}
= \lim_{z \to i} \frac{d}{dz}\!\left[ \frac{1}{(z+i)^2} \right]
= \frac{-2}{(2i)^3}
= \frac{-2}{-8i}
= \frac{1}{4i}.
$$
So the integral is $2\pi i \cdot 1/(4i) = \pi/2$.  ✓

## 5.4 — A trigonometric integral

$$
\int_0^{2\pi} \frac{d\theta}{2 + \cos\theta}
$$

Substitute $z = e^{i\theta}$, so $d\theta = dz/(iz)$ and
$\cos\theta = (z + z^{-1})/2$.  The integral becomes a contour
integral around the unit circle:
$$
\oint_{|z|=1} \frac{dz / (iz)}{2 + (z + z^{-1})/2}
= \frac{2}{i} \oint_{|z|=1} \frac{dz}{z^2 + 4z + 1}.
$$
The denominator factors as $(z - (-2 + \sqrt3))(z - (-2 - \sqrt3))$.
Only the root $-2 + \sqrt3 \approx -0.27$ lies inside the unit
circle.  Residue there: $1/(2(-2+\sqrt3) + 4) = 1/(2\sqrt3)$.

So the integral is $(2/i) \cdot 2\pi i / (2\sqrt3) = 2\pi/\sqrt3$.

```lean
def trigIntegral : ℝ := Id.run do
  let N := 2000
  let dθ := 2 * Real.pi / (N : ℝ)
  let mut acc : ℝ := 0
  for k in [:N] do
    let θ : ℝ := (k : ℝ) * dθ
    acc := acc + dθ / (2 + Real.cos θ)
  pure acc

#eval trigIntegral
-- Should match 2π/√3 ≈ 3.6276.
#eval 2 * Real.pi / Real.sqrt 3
```

## 5.5 — Formal sketch

Mathlib's residue theorem is `Complex.residue_theorem` (sometimes
named differently between versions; if your snapshot doesn't have it,
scout: `#findDecl "residue" 0 20`).

The "real integral via residues" lemmas are sparser — most of the
content is *applications* of the residue theorem rather than a
single named theorem.  In practice you build them per integral:
identify the contour, identify the poles inside, sum the residues.

```lean
example :
    (∫ x : ℝ, 1 / (x^2 + 1)) = Real.pi := by
  -- Mathlib has this as `MeasureTheory.integral_one_div_one_add_sq`
  -- or similar; the residue-theorem proof is one approach, the
  -- arctan-substitution proof another.
  sorry
```

## 5.6 — Prove it yourself

1. Use the residue theorem to evaluate
   $\displaystyle \int_{-\infty}^{\infty} \frac{dx}{x^4 + 1}$.
   (Hint: four poles, two in the upper half plane, $e^{i\pi/4}$
   and $e^{3i\pi/4}$.)
2. Compute $\displaystyle \int_0^\infty \frac{\sin x}{x}\,dx$ by
   integrating $e^{iz}/z$ around an indented semicircle.  This is
   the Dirichlet integral; the answer is $\pi/2$.  (Hint: the
   indentation around $z=0$ contributes $-i\pi \cdot \operatorname*{Res}_0(e^{iz}/z)
   = -i\pi$.)
3. (Hard) Evaluate $\displaystyle \int_0^\infty \frac{x^{a-1}}{1+x}\,dx$ for
   $0 < a < 1$.  Use a keyhole contour that avoids the branch cut of
   $z^{a-1}$ along the positive real axis.  The answer is
   $\pi/\sin(\pi a)$ — one of the most beautiful identities in the
   subject.

Exercise 3 alone is worth a chapter; it's the bridge from complex
analysis to the **Gamma function**, $\Gamma$-reflection, and the
analytic continuation of $\zeta(s)$.

## 5.7 — Frontier link

- The **Mellin transform**, which underwrites Tauberian theorems and
  almost every closed-form result in analytic number theory, is a
  contour integral interpretation of "integrate against $x^{s-1}$."
- **Asymptotic expansion** of integrals (saddle-point, steepest
  descent) starts from the same contour-deformation idea: you find a
  path on which the integrand peaks sharply, then expand.
- In ML, **rational approximations** of activation functions or PDE
  Green's functions can be derived by writing the target as a
  contour integral and discretising along the contour: this is the
  **rational Krylov method** family.

## What's next

We've extracted real-world answers from imaginary paths.  Chapter 6
will go the other way: take a non-trivial property of the *winding*
of a contour and turn it into a counting principle — the argument
principle, which counts zeros of analytic functions without ever
finding them explicitly.
