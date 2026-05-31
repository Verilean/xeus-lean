# Chapter 4 — Contour Integration

Three chapters in, we have rotation-and-scaling (Ch1), the four-block
factorisation of Möbius transformations (Ch2), and a sphere on which
"line" and "circle" mean the same thing (Ch3).

Now we change the question: instead of *moving* points around the
plane, we *integrate* a function along a path through it.  The value
of an integral around a closed loop depends on what the loop is
wrapped around — topology-aware calculus.

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

```lean
%load mathlib
```

```lean
import Mathlib.MeasureTheory.Integral.CircleIntegral
```

## 4.1 — A contour integral, slowly

Pick a smooth path $\gamma : [a, b] \to \mathbb{C}$ and continuous
$f : \mathbb{C} \to \mathbb{C}$.  The contour integral is

$$
\oint_\gamma f(z)\,dz \;=\; \int_a^b f(\gamma(t))\,\gamma'(t)\,dt.
$$

That second integral is just a Riemann integral of a complex-valued
function of a real variable.

Picture: a path winding once around the origin, $\gamma(t) = e^{it}$
for $t \in [0, 2\pi]$.

```lean
#html "<svg viewBox='-1.6 -1.6 3.2 3.2' width='360' style='background:#f4f4f8'>
  <line x1='-1.5' y1='0' x2='1.5' y2='0' stroke='#aaa' stroke-width='0.02'/>
  <line x1='0' y1='-1.5' x2='0' y2='1.5' stroke='#aaa' stroke-width='0.02'/>
  <circle cx='0' cy='0' r='1' fill='none' stroke='#268' stroke-width='0.04'/>
  <circle cx='0' cy='0' r='0.05' fill='#c25'/>
  <text x='-1.4' y='-0.15' fill='#268' font-size='0.2'>γ(t) = e^{it}</text>
  <text x='0.05' y='-0.1' fill='#c25' font-size='0.2'>0</text>
</svg>"
```

## 4.2 — The single most important contour integral

Compute $\oint_\gamma \frac{1}{z}\,dz$ around the unit circle:

- $\gamma(t) = e^{it}$, $\gamma'(t) = i e^{it}$
- $1/\gamma(t) = e^{-it}$
- integrand: $e^{-it} \cdot i e^{it} = i$
- integral: $\int_0^{2\pi} i\,dt = 2\pi i$

```lean
def integralOneOverZ : ComplexF := Id.run do
  let N : Nat := 200
  let dt : Float := 2.0 * PI / Float.ofNat N
  let mut acc : ComplexF := 0
  for k in [:N] do
    let t : Float := Float.ofNat k * dt
    let γ : ComplexF := (ofReal t * I).exp
    let γ' : ComplexF := I * γ                 -- (e^{it})' = i·e^{it}
    let f : ComplexF := 1 / γ
    acc := acc + f * γ' * ofReal dt
  pure acc

#eval integralOneOverZ
-- Re ≈ 0, Im ≈ 2π ≈ 6.283
```

The answer — $2\pi i$ — is the cornerstone of all contour
integration.  Every other contour integral worth computing reduces to
"how many times does this thing look like $1/z$ near each
singularity?"

## 4.3 — Cauchy's integral theorem (the easy half)

For $f$ holomorphic everywhere inside a closed contour $\gamma$:

$$
\oint_\gamma f(z)\,dz = 0.
$$

Numerical demo with $f(z) = z^2$ on the unit circle:

```lean
def integralOfZSquared : ComplexF := Id.run do
  let N : Nat := 200
  let dt : Float := 2.0 * PI / Float.ofNat N
  let mut acc : ComplexF := 0
  for k in [:N] do
    let t : Float := Float.ofNat k * dt
    let γ : ComplexF := (ofReal t * I).exp
    let γ' : ComplexF := I * γ
    let f : ComplexF := γ * γ
    acc := acc + f * γ' * ofReal dt
  pure acc

#eval integralOfZSquared
-- Re ≈ 0, Im ≈ 0 (only floating-point noise)
```

The contrast with §4.2 is the punchline: **only integrals
"encircling a singularity" are non-zero**.

## 4.4 — Residues, glimpsed

The **residue** of $f$ at an isolated singularity $z_0$ is the
coefficient of the $(z - z_0)^{-1}$ term in the Laurent expansion.

Cauchy's residue theorem:

$$
\oint_\gamma f(z)\,dz \;=\; 2\pi i \sum_k \operatorname*{Res}_{z=z_k} f(z),
$$

summing over singularities inside $\gamma$ with winding number.

For $f(z) = 1/z$, $\operatorname*{Res}_{z=0} f = 1$, so the integral
is $2\pi i \cdot 1 = 2\pi i$.  Which is what §4.2 computed.

## 4.5 — Play: deform the path

The integral stays the same as long as the path doesn't cross a
singularity.  Try $1/z$ around a **square** contour of side 2.

```lean
def integralAroundSquare : ComplexF := Id.run do
  let N : Nat := 50  -- per edge
  let dt : Float := 2.0 / Float.ofNat N
  let mut acc : ComplexF := 0
  -- bottom edge: z = -1 + t·1, t ∈ [0, 2], dz = dt
  for k in [:N] do
    let t : Float := Float.ofNat k * dt
    let z : ComplexF := ofReal (-1.0 + t)
    let dz : ComplexF := ofReal dt
    acc := acc + (1 / z) * dz
  -- right edge: z = 1 + i·(-1 + t), dz = i·dt
  for k in [:N] do
    let t : Float := Float.ofNat k * dt
    let z : ComplexF := 1 + ofReal (-1.0 + t) * I
    let dz : ComplexF := I * ofReal dt
    acc := acc + (1 / z) * dz
  -- top edge: z = (1 - t) + i, dz = -dt
  for k in [:N] do
    let t : Float := Float.ofNat k * dt
    let z : ComplexF := ofReal (1.0 - t) + I
    let dz : ComplexF := ofReal (-dt)
    acc := acc + (1 / z) * dz
  -- left edge: z = -1 + i·(1 - t), dz = -i·dt
  for k in [:N] do
    let t : Float := Float.ofNat k * dt
    let z : ComplexF := (ofReal (-1.0)) + ofReal (1.0 - t) * I
    let dz : ComplexF := I * ofReal (-dt)
    acc := acc + (1 / z) * dz
  pure acc

#eval integralAroundSquare
-- Re ≈ 0, Im ≈ 2π — same answer as §4.2.
```

Different path, same answer — deformation invariance.

## 4.6 — Formal sketch

```lean
-- Mathlib's `circleIntegral` packages "∮_{|z-c|=r}" as a measure-
-- theoretic integral.  This statement type-checks; the lemma name
-- moves around between versions, so scout with #findDecl.
example (c : ℂ) (r : ℝ) (hr : 0 < r) : True := by
  -- Expected lemma name: `circleIntegral_sub_inv_smul_eq_two_pi_I_smul`
  -- or similar.  #findDecl "circleIntegral" 0 20
  trivial
```

## 4.7 — Prove it yourself

1. Compute $\oint_\gamma z^n\,dz$ around the unit circle for $n =
   0, 1, 2, -1, -2$.  Predict via §4.2/§4.3, then verify
   numerically (modify `integralOfZSquared` to use `z^n`).
2. Show that for any holomorphic $f$ on the closed unit disk,
   $f(0) = \frac{1}{2\pi i}\oint_{|z|=1} \frac{f(z)}{z}\,dz$.  Hint:
   substitute the Taylor series of $f$, integrate term by term.
3. (Hard) For $f(z) = e^z$, compute
   $\oint_{|z|=1} e^z / z^{n+1}\,dz$ in closed form for $n = 0, 1, 2, \dots$
   and notice you've recovered the Taylor coefficients of $e^z$.

## 4.8 — Frontier link

Contour integration is the engine room of CFT, QFT (Feynman $i\epsilon$),
analytic number theory, and numerical analysis (rational
approximation).  Every closed-form integral computation in modern
physics passes through this picture.

## What's next

Chapter 5 uses the same machinery to evaluate real integrals on
$\mathbb{R}$ that elementary calculus can't touch — the residue
theorem's best party trick.
