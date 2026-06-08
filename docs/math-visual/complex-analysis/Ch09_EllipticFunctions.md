# Chapter 9 — Elliptic Functions and Tori

A torus $T_\tau = \mathbb{C} / (\mathbb{Z} + \tau\mathbb{Z})$ is the
simplest closed Riemann surface that *isn't* the disk.  Functions on
it must be *doubly periodic* with periods $1$ and $\tau$.  The
non-trivial ones are **elliptic functions**.

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
@[inline] def neg (a : ComplexF) : ComplexF := ⟨-a.re, -a.im⟩
def I : ComplexF := ⟨0, 1⟩
def ofReal (r : Float) : ComplexF := ⟨r, 0⟩
instance : Add ComplexF := ⟨add⟩
instance : Sub ComplexF := ⟨sub⟩
instance : Mul ComplexF := ⟨mul⟩
instance : Div ComplexF := ⟨div⟩
instance : Neg ComplexF := ⟨neg⟩
instance : OfNat ComplexF n where ofNat := ⟨Float.ofNat n, 0⟩
end ComplexF
open ComplexF
```

## 9.1 — The torus picture

A torus = a parallelogram with opposite edges identified:

```lean
#html "<svg viewBox='-1 -0.5 5 3.5' width='480' style='background:#f4f4f8'>
  <polygon points='0.5,2.5 2,0.5 3.5,0.5 2,2.5' fill='#7ec97e44' stroke='#3a3' stroke-width='0.04'/>
  <text x='0.1' y='2.85' fill='#c25' font-size='0.25'>0</text>
  <text x='3.6' y='0.4' fill='#c25' font-size='0.25'>1+τ</text>
  <text x='2.1' y='0.4' fill='#c25' font-size='0.25'>τ</text>
  <text x='2.0' y='2.85' fill='#c25' font-size='0.25'>1</text>
</svg>"
```

A holomorphic function on the torus = a doubly periodic holomorphic
function on $\mathbb{C}$.  By maximum modulus on a compact surface,
this must be constant.  So the interesting functions on a torus are
**meromorphic**, not holomorphic.

## 9.2 — The Weierstrass $\wp$ function (truncated)

The full Weierstrass function:

$$
\wp(z; \tau) = \frac{1}{z^2} + \sum_{(m,n) \neq (0,0)}
\left[ \frac{1}{(z - m - n\tau)^2} - \frac{1}{(m + n\tau)^2} \right].
$$

Doubly periodic, double pole at every lattice point.  Satisfies
$(\wp')^2 = 4\wp^3 - g_2 \wp - g_3$.  The cubic
$y^2 = 4x^3 - g_2 x - g_3$ is an *elliptic curve*.  Tori ≡ elliptic
curves.

Numerical truncation (sum over $|m|, |n| \le N$):

```lean
def wpApprox (z τ : ComplexF) (N : Nat) : ComplexF := Id.run do
  let Nint : Int := Int.ofNat N
  let mut acc : ComplexF := 1 / (z * z)
  for m in [(-Nint : Int)..(Nint + 1)] do
    for n in [(-Nint : Int)..(Nint + 1)] do
      if m == 0 ∧ n == 0 then continue
      let mC : ComplexF := ofReal (Float.ofInt m)
      let nC : ComplexF := ofReal (Float.ofInt n)
      let lat : ComplexF := mC + nC * τ
      let t1 : ComplexF := 1 / ((z - lat) * (z - lat))
      let t2 : ComplexF := 1 / (lat * lat)
      acc := acc + (t1 - t2)
  pure acc

-- ℘(1/2; i) for the square torus.  Slowly convergent — N=4 is a rough
-- ballpark; doubling N tightens it.
#eval wpApprox (ofReal 0.5) I 4
```

## 9.3 — The modular parameter $\tau$

Tori $T_{\tau_1}, T_{\tau_2}$ are conformally equivalent iff their
lattices are equivalent.  The action of $\mathrm{SL}_2(\mathbb{Z})$
on $\tau$:

$$
\tau \mapsto \frac{a\tau + b}{c\tau + d}, \quad ad - bc = 1.
$$

The moduli space is $\mathbb{H} / \mathrm{SL}_2(\mathbb{Z})$.

```lean
def modSL2 (a b c d : Int) (τ : ComplexF) : ComplexF :=
  let aC : ComplexF := ofReal (Float.ofInt a)
  let bC : ComplexF := ofReal (Float.ofInt b)
  let cC : ComplexF := ofReal (Float.ofInt c)
  let dC : ComplexF := ofReal (Float.ofInt d)
  (aC * τ + bC) / (cC * τ + dC)

#eval modSL2 0 (-1) 1 0 I       -- τ → -1/τ: i → i (square lattice fixed!)
#eval modSL2 1 1 0 1 I          -- τ → τ + 1
```

## 9.4 — Play: lattice symmetries

The **square** lattice $\tau = i$ has $90°$ symmetry.  The
**hexagonal** lattice $\tau = e^{i\pi/3}$ has $60°$.  They're the two
lattices with extra automorphisms.

## 9.5 — Formal sketch

```text
%load mathlib
```

```lean
import Mathlib.NumberTheory.ModularForms.Basic

example : Type := UpperHalfPlane

example (γ : Matrix.SpecialLinearGroup (Fin 2) ℤ) (τ : UpperHalfPlane) :
    UpperHalfPlane := γ • τ
```

## 9.6 — Prove it yourself

1. Verify (using `wpApprox` and the substitution $z \mapsto -z$) that
   $\wp(-z) = \wp(z)$.  Even function.
2. Show the sum of residues of an elliptic function over a
   fundamental parallelogram is zero.
3. (Hard) Show $\wp$ has order 2: every value in $\mathbb{C} \cup
   \{\infty\}$ is taken exactly twice per fundamental parallelogram.

## 9.7 — Frontier link

- **Modularity theorem** (Wiles): every elliptic curve over $\mathbb{Q}$
  corresponds to a modular form.
- **Mirror symmetry**: $\tau \leftrightarrow -1/\tau$.
- **Lattice cryptography**: hardness of lattice problems in $\mathbb{R}^n$.

## What's next

Chapter 10 closes the arc by giving the upper half plane the geometry
it has always wanted: hyperbolic geometry, on which Möbius
transformations from chapters 2–3 act as isometries.
