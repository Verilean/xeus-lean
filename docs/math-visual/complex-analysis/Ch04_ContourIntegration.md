# Chapter 4 — Contour Integration

Three chapters in, we have rotation-and-scaling (Ch1), the four-block
factorisation of Möbius transformations (Ch2), and a sphere on which
"line" and "circle" mean the same thing (Ch3).

Now we change the question: instead of *moving* points around the
plane, we *integrate* a function along a path through it.  This is
where complex analysis stops being geometry-of-motion and starts being
**topology-aware calculus**: the value of an integral around a closed
loop depends on what the loop is wrapped around, not how exactly it
got there.

```lean
%load mathlib
```

```lean
import Mathlib.Analysis.Complex.Basic
import Mathlib.Analysis.SpecialFunctions.Complex.Circle
import Mathlib.MeasureTheory.Integral.CircleIntegral
open Complex Real
```

## 4.1 — A contour integral, slowly

Pick a smooth path $\gamma : [a, b] \to \mathbb{C}$ and a continuous
function $f : \mathbb{C} \to \mathbb{C}$.  The contour integral of $f$
along $\gamma$ is

$$
\oint_\gamma f(z)\,dz \;=\; \int_a^b f(\gamma(t))\,\gamma'(t)\,dt.
$$

That second integral is just an ordinary Riemann integral of a complex-
valued function of a real variable.  Nothing exotic.  The interesting
behaviour comes from what happens when $\gamma$ is *closed* (i.e.
$\gamma(a) = \gamma(b)$) and you slide $f$ through different choices.

Picture: a path winding once around the origin, with the
parametrisation $\gamma(t) = e^{it}$ for $t \in [0, 2\pi]$.

```lean
#html "<svg viewBox='-1.6 -1.6 3.2 3.2' width='360' style='background:#f4f4f8'>
  <line x1='-1.5' y1='0' x2='1.5' y2='0' stroke='#aaa' stroke-width='0.02'/>
  <line x1='0' y1='-1.5' x2='0' y2='1.5' stroke='#aaa' stroke-width='0.02'/>
  <circle cx='0' cy='0' r='1' fill='none' stroke='#268' stroke-width='0.04'/>
  <circle cx='0' cy='0' r='0.05' fill='#c25'/>
  <text x='-1.4' y='-0.15' fill='#268' font-size='0.2'>γ(t) = e^{it}</text>
  <text x='0.05' y='-0.1' fill='#c25' font-size='0.2'>0</text>
  <!-- direction arrow -->
  <path d='M 0.95 -0.3 A 1 1 0 0 0 0.7 -0.7' fill='none' stroke='#268' stroke-width='0.04'/>
  <polygon points='0.7,-0.7 0.7,-0.55 0.85,-0.65' fill='#268'/>
</svg>"
```

## 4.2 — The single most important contour integral

Compute $\oint_\gamma \frac{1}{z}\,dz$ around the unit circle:

- $\gamma(t) = e^{it}$, $\gamma'(t) = i e^{it}$
- $\dfrac{1}{\gamma(t)} = e^{-it}$
- integrand: $e^{-it} \cdot i e^{it} = i$
- integral: $\int_0^{2\pi} i\,dt = 2\pi i$

```lean
-- Quick numerical sanity-check: sample the integrand on 100 equally-
-- spaced points and sum, scaled by Δt.
def numericalIntegral : ℂ := Id.run do
  let N := 100
  let dt := 2 * Real.pi / (N : ℝ)
  let mut acc : ℂ := 0
  for k in [:N] do
    let t : ℝ := dt * (k : ℝ)
    let γ : ℂ := Complex.exp (t * I)
    let γ' : ℂ := I * γ                 -- (e^{it})' = i·e^{it}
    let f : ℂ := γ⁻¹
    acc := acc + f * γ' * dt
  pure acc

#eval numericalIntegral
-- Should land near (0, 2π) ≈ (0, 6.28).  Try it.
```

That answer — $2\pi i$ — is the cornerstone of all of contour
integration.  Every other contour integral worth computing reduces to
"how many times does this thing look like $1/z$ near each singularity?"

## 4.3 — Cauchy's integral theorem (the easy half)

For a function $f$ that's holomorphic everywhere inside a closed
contour $\gamma$, the integral around the contour is **zero**:

$$
\oint_\gamma f(z)\,dz = 0.
$$

Why?  Stokes' theorem on the real-and-imaginary-parts decomposition
collapses the integrand exactly when the Cauchy–Riemann equations
hold, which is the definition of holomorphic.

Numerical demo with $f(z) = z^2$ on the unit circle:

```lean
def integralOfZSquared : ℂ := Id.run do
  let N := 100
  let dt := 2 * Real.pi / (N : ℝ)
  let mut acc : ℂ := 0
  for k in [:N] do
    let t : ℝ := dt * (k : ℝ)
    let γ : ℂ := Complex.exp (t * I)
    let γ' : ℂ := I * γ
    let f : ℂ := γ * γ
    acc := acc + f * γ' * dt
  pure acc

#eval integralOfZSquared
-- Both components should be near 0 (numerical noise only).
```

The contrast with §4.2 is the punchline: **only the integrals that
"encircle a singularity" are non-zero**.  And how non-zero they are is
determined by exactly one number per singularity — the residue.

## 4.4 — Residues, glimpsed

The **residue** of $f$ at an isolated singularity $z_0$ is the
coefficient of the $(z - z_0)^{-1}$ term in the Laurent expansion of
$f$ around $z_0$.  Concretely:

$$
\operatorname*{Res}_{z=z_0} f(z) \;=\; \frac{1}{2\pi i} \oint_\gamma f(z)\,dz
$$

for any small loop $\gamma$ enclosing only $z_0$.

For our example $f(z) = 1/z$:

$$
\operatorname*{Res}_{z=0} \frac{1}{z} = 1.
$$

For $f(z) = 1/z^n$ with $n \neq 1$, the residue at $0$ is $0$ —
that's why those integrals vanish.

Cauchy's residue theorem packages this into the master formula:

$$
\oint_\gamma f(z)\,dz \;=\; 2\pi i \sum_{k} \operatorname*{Res}_{z=z_k} f(z),
$$

where the sum is over singularities $z_k$ inside $\gamma$ (counted
with winding number).

## 4.5 — Play: change the path

The Cauchy theorem says: **as long as you don't cross a singularity,
the integral is the same**.  Watch what that does on a numerical level.

```lean
-- Integral of 1/z around a *square* contour of side 2, centred at 0.
-- We sample each of the four edges densely.
def integralAroundSquare : ℂ := Id.run do
  let N := 50  -- per edge
  let dt : ℝ := 2.0 / (N : ℝ)
  let mut acc : ℂ := 0
  -- bottom edge: z = -1 + t·1   for t in [0, 2]
  for k in [:N] do
    let t : ℝ := (k : ℝ) * dt
    let z : ℂ := -1 + t
    let dz : ℂ := 1 * dt
    acc := acc + (z⁻¹) * dz
  -- right edge: z = 1 + i·t   for t in [-1, 1]
  for k in [:N] do
    let t : ℝ := -1 + (k : ℝ) * dt
    let z : ℂ := 1 + t * I
    let dz : ℂ := I * dt
    acc := acc + (z⁻¹) * dz
  -- top edge: z = 1 - t   (going right to left), t in [0, 2]
  for k in [:N] do
    let t : ℝ := (k : ℝ) * dt
    let z : ℂ := 1 - t + I
    let dz : ℂ := -1 * dt
    acc := acc + (z⁻¹) * dz
  -- left edge: z = -1 + i·(1 - t)
  for k in [:N] do
    let t : ℝ := (k : ℝ) * dt
    let z : ℂ := -1 + (1 - t) * I
    let dz : ℂ := -I * dt
    acc := acc + (z⁻¹) * dz
  pure acc

#eval integralAroundSquare
-- Should also land near (0, 2π) ≈ (0, 6.28).  Different path, same
-- answer — exactly because both paths wind once around z = 0 and
-- 1/z has no other singularities to worry about.
```

If you shrink the square down to a tiny one, or stretch it to a giant
one, the answer is *still* $2\pi i$.  That's deformation invariance:
the integral depends only on the homotopy class of the path in
$\mathbb{C} \setminus \{0\}$.

## 4.6 — Formal sketch

Mathlib's `circleIntegral` (in `Mathlib.MeasureTheory.Integral.
CircleIntegral`) packages "$\oint_{|z-c|=r}$" as a measure-theoretic
integral.  The Cauchy formula sits a few imports deeper.

```lean
-- A formal version of "∮ dz/(z - c) = 2πi" for a circle around c.
example (c : ℂ) (r : ℝ) (hr : 0 < r) :
    (∮ z in C(c, r), (z - c)⁻¹) = 2 * π * I := by
  -- Mathlib's `circleIntegral_sub_inv_smul_eq` or
  -- `circleIntegral_sub_center_inv_div_two_pi_I` is the lemma to find.
  -- If neither name is recognised, scout with:
  --   #findDecl "circleIntegral" 0 20
  sorry
```

## 4.7 — Prove it yourself

1. Compute $\oint_\gamma z^n\,dz$ around the unit circle for $n =
   0, 1, 2, -1, -2$.  Predict the answers using §4.2/§4.3, then verify
   numerically.
2. Show that for any holomorphic $f$ on the closed unit disk,
   $$ f(0) = \frac{1}{2\pi i} \oint_{|z|=1} \frac{f(z)}{z}\,dz. $$
   (Hint: substitute the Taylor series of $f$, integrate term by term.)
   This is Cauchy's integral formula in its simplest case.
3. (Hard) For $f(z) = e^z$, compute $\oint_{|z|=1} e^z / z^{n+1}\,dz$
   for $n = 0, 1, 2, \dots$ in closed form, and notice that you've
   just recovered Taylor coefficients.

## 4.8 — Frontier link

Contour integration is the engine room of:

- **Conformal field theory**: correlation functions in 2D CFT are
  contour integrals of operator products.
- **Quantum field theory in physics**: propagators are contour
  integrals on the real line that you push into the complex plane
  to avoid singularities (the Feynman $i\epsilon$ prescription).
- **Number theory**: the explicit formula relating zeros of
  $\zeta(s)$ to the prime-counting function is a contour integral
  identity.  Anything proof-assistant-relevant about the Riemann
  hypothesis sits one layer above this chapter.
- **Numerical analysis / ML**: rational approximation of arbitrary
  functions via Padé approximants uses the same residue technology
  inside out.

## What's next

Chapter 5 will exploit this machinery to compute integrals on the
*real* line that elementary calculus can't touch — the residue
theorem's most-used party trick.
