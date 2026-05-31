# Chapter 9 — Elliptic Functions and Tori

Chapter 8 said: every simply-connected proper subset of $\mathbb{C}$ is
conformally a disk.

So what *isn't* conformally a disk?

The simplest answer is: **a torus**.  Not a torus drawn in 3D space
(donut shape), but a torus as a quotient surface: take the complex
plane and identify $z \sim z + 1 \sim z + \tau$ for some
$\mathrm{Im}\,\tau > 0$.  The result is a closed Riemann surface
with no boundary — it can't be the disk, because the disk has a
boundary.

Functions on a torus, viewed back in $\mathbb{C}$, are exactly
**doubly periodic** functions, with periods $1$ and $\tau$.  The
non-trivial ones (called *elliptic functions*) are simultaneously
some of the most beautiful objects in classical mathematics and the
seed crystal of arithmetic geometry.

```lean
%load mathlib
```

```lean
import Mathlib.Analysis.Complex.Basic
import Mathlib.NumberTheory.ModularForms.Basic
open Complex Real
```

## 9.1 — The torus picture

A torus $T_\tau = \mathbb{C} / (\mathbb{Z} + \tau\mathbb{Z})$.
Picture: a parallelogram with opposite edges identified.

```lean
#html "<svg viewBox='-1 -0.5 5 3.5' width='480' style='background:#f4f4f8'>
  <polygon points='0.5,2.5 2,0.5 3.5,0.5 2,2.5' fill='#7ec97e44' stroke='#3a3' stroke-width='0.04'/>
  <circle cx='0.5' cy='2.5' r='0.07' fill='#c25'/>
  <text x='0.1' y='2.85' fill='#c25' font-size='0.25'>0</text>
  <circle cx='3.5' cy='0.5' r='0.07' fill='#c25'/>
  <text x='3.6' y='0.4' fill='#c25' font-size='0.25'>1+τ</text>
  <circle cx='2' cy='0.5' r='0.07' fill='#c25'/>
  <text x='2.1' y='0.4' fill='#c25' font-size='0.25'>τ</text>
  <circle cx='2' cy='2.5' r='0.07' fill='#c25'/>
  <text x='2.0' y='2.85' fill='#c25' font-size='0.25'>1</text>
  <text x='-0.85' y='3.3' fill='#444' font-size='0.22'>opposite edges identified  ↑ ↓  ← →</text>
</svg>"
```

A function on $T_\tau$ is a function $f : \mathbb{C} \to \mathbb{C}$
satisfying

$$
f(z + 1) = f(z) = f(z + \tau).
$$

Constant functions trivially satisfy this.  Is there a *non-constant*
holomorphic function on the torus?  Here's the catch: a holomorphic
function on a *compact* Riemann surface is automatically constant
(maximum modulus principle, §7.5).  So there are no non-constant
holomorphic functions on a torus.

We must allow *poles*: meromorphic doubly-periodic functions are the
interesting ones.

## 9.2 — The Weierstrass $\wp$ function

The simplest elliptic function is Weierstrass's $\wp$ (script "p"):

$$
\wp(z; \tau) = \frac{1}{z^2} + \sum_{\substack{(m,n) \in \mathbb{Z}^2 \\ (m,n) \neq (0,0)}}
\left[ \frac{1}{(z - m - n\tau)^2} - \frac{1}{(m + n\tau)^2} \right].
$$

That sum is conditionally convergent for a clear reason: the
$1/(m + n\tau)^2$ subtraction cancels the leading $1/(m+n\tau)^2$
asymptotic of each term so the sum makes sense.

Properties:

- Double poles at every lattice point $m + n\tau$.
- Meromorphic, doubly periodic with periods $1$ and $\tau$.
- Satisfies a differential equation
  $(\wp')^2 = 4\wp^3 - g_2 \wp - g_3$
  where $g_2, g_3$ are lattice constants.

That cubic, $y^2 = 4x^3 - g_2 x - g_3$, is the equation of an
**elliptic curve**.  And the map
$z \mapsto (\wp(z), \wp'(z))$
is a bijection from the torus to the elliptic curve.

In one move: the *torus as a quotient surface* and the *elliptic
curve as a cubic equation* are the same object.  Up to the
identification you can do analytic geometry on tori or algebraic
geometry on cubics; they're literally the same.

```lean
-- Numerical truncated approximation of ℘(z; τ) summing |m|,|n| ≤ N.
def wpApprox (z τ : ℂ) (N : Nat) : ℂ := Id.run do
  let mut acc : ℂ := 1 / (z * z)
  for m in [(-(N : Int))..N+1] do
    for n in [(-(N : Int))..N+1] do
      if m == 0 ∧ n == 0 then continue
      let lat : ℂ := (m : ℂ) + (n : ℂ) * τ
      let term1 : ℂ := 1 / ((z - lat) * (z - lat))
      let term2 : ℂ := 1 / (lat * lat)
      acc := acc + (term1 - term2)
  pure acc

-- For τ = i (the square torus), ℘(1/2; i) should be a small real
-- number near 7 (one of the special values).
#eval wpApprox 0.5 I 6
-- (The series is slowly convergent — N = 6 is enough for a rough
-- ballpark; doubling N tightens it.)
```

## 9.3 — The modular parameter $\tau$

Two tori $T_{\tau_1}$ and $T_{\tau_2}$ are conformally equivalent if
and only if their lattices are equivalent.  Lattice equivalence is
governed by the group $\mathrm{SL}_2(\mathbb{Z})$ acting on $\tau$ by

$$
\tau \mapsto \frac{a\tau + b}{c\tau + d}, \quad ad - bc = 1.
$$

So the *moduli space* of tori is the quotient of the upper half
plane by $\mathrm{SL}_2(\mathbb{Z})$:

$$
\mathcal{M}_1 = \mathbb{H} / \mathrm{SL}_2(\mathbb{Z}).
$$

This is a Riemann surface itself.  Functions on it are
**modular functions**; functions transforming with a specific weight
are **modular forms**.

The modular world is the natural setting for:

- Eisenstein series and the $j$-invariant
- Theta functions
- The space of Modular forms of given weight and level (a finite-
  dimensional vector space — surprising)
- Hecke operators acting on those spaces

The Hecke eigenforms in this picture are *literally* the modern
language for elliptic curves over $\mathbb{Q}$, and the bridge to
Fermat's Last Theorem.

## 9.4 — Play: lattice symmetries

```lean
-- For τ = i (square lattice), check that the substitution
--   τ → -1/τ
-- gives an equivalent torus.  Apply it to a few values.
def modSL2 (a b c d : ℤ) (τ : ℂ) : ℂ :=
  ((a : ℂ)*τ + (b : ℂ)) / ((c : ℂ)*τ + (d : ℂ))

#eval modSL2 0 (-1) 1 0 I       -- -1/i = i: square lattice is fixed!
#eval modSL2 1 1 0 1 I          -- τ → τ + 1, also a fundamental transformation
```

For the **square lattice** $\tau = i$, there's a $90°$ rotation
symmetry; for the **hexagonal lattice** $\tau = e^{i\pi/3}$, there's a
$60°$ symmetry.  These are the two lattices with extra automorphisms,
and they show up everywhere in physics (Kagome / honeycomb), tilings,
and number theory ($j$-invariant takes special values).

## 9.5 — Formal sketch

Mathlib has the upper half plane (`UpperHalfPlane`), modular group
action, and at least the start of modular forms in
`Mathlib.NumberTheory.ModularForms`.  Elliptic functions per se are
not fully formalised at the time of writing; the lattice / modular
setup is.

```lean
-- The upper half plane as a Mathlib structure:
example : Type := UpperHalfPlane

-- The modular group SL₂(ℤ) acts on it:
example (γ : Matrix.SpecialLinearGroup (Fin 2) ℤ) (τ : UpperHalfPlane) :
    UpperHalfPlane := γ • τ
```

The proof that $T_{\tau_1}$ and $T_{\tau_2}$ are conformally
equivalent iff $\tau_1$ and $\tau_2$ are in the same orbit is a
theorem that fits in a few dozen lines once the lattices are set up
correctly.

## 9.6 — Prove it yourself

1. (Easy) Verify that the function $\wp$, as defined by the series in
   §9.2, is even: $\wp(-z) = \wp(z)$.  (Hint: $(-z - m - n\tau)^2 =
   (z + m + n\tau)^2$; replace the dummy index pair $(m,n)$ by
   $(-m,-n)$.)
2. (Medium) Show that the sum of residues of an elliptic function
   over a fundamental parallelogram is zero.  (Hint: integrate
   around the boundary, opposite sides contribute opposite signs
   because of periodicity.  Then use the residue theorem.)
3. (Hard) Show that $\wp$ has order 2 in the sense that every value
   in $\mathbb{C} \cup \{\infty\}$ is taken exactly twice per
   fundamental parallelogram.  Combine with §9.6.2.

## 9.7 — Frontier link

- **Modularity theorem (Taylor–Wiles).**  Every elliptic curve over
  $\mathbb{Q}$ corresponds to a modular form.  Fermat's last
  theorem follows.  The whole proof is built on rigidity (§7) +
  classification of tori (§9).
- **Mirror symmetry.**  String theory's most striking mathematical
  spin-off relates pairs of Calabi–Yau threefolds via modular
  duality.  The 1D-baby case (mirror pairs of tori) is exactly
  $\tau \leftrightarrow -1/\tau$ from §9.4.
- **Lattice cryptography.**  Recent "post-quantum" cryptosystems
  rely on hard problems in lattices in $\mathbb{R}^n$, but the
  testing ground for hardness conjectures often comes back to
  $\mathrm{SL}_2(\mathbb{Z})$-orbits and their geometric
  invariants.
- **Special-function ML.**  Theta-function activations have been
  proposed for ML models with periodic structure; they generalise
  Fourier features in a way that respects modular symmetry.

## What's next

The final chapter (10) will return to where we started — the upper
half plane — and give it the geometry it has always wanted: the
**hyperbolic plane**.  Möbius transformations from chapters 2 and 3
become isometries; lines become hyperbolic geodesics; and the
modular surface of chapter 9 becomes a finite-volume hyperbolic
quotient.  Complex analysis closes with the most non-Euclidean
geometry on offer.
