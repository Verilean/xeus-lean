# Chapter 8 — The Riemann Mapping Theorem

> **Every** simply-connected proper open subset of $\mathbb{C}$ is
> biholomorphic to the open unit disk.

Two domains that *look* nothing alike are conformally identical, up
to a Möbius transformation.

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
def I : ComplexF := ⟨0, 1⟩
def ofReal (r : Float) : ComplexF := ⟨r, 0⟩
instance : Add ComplexF := ⟨add⟩
instance : Sub ComplexF := ⟨sub⟩
instance : Mul ComplexF := ⟨mul⟩
instance : Div ComplexF := ⟨div⟩
instance : OfNat ComplexF n where ofNat := ⟨Float.ofNat n, 0⟩
end ComplexF
open ComplexF
```

## 8.1 — Why this is surprising

```lean
#html "<svg viewBox='-4.5 -1.5 12 4.5' width='600' style='background:#f4f4f8'>
  <g fill='#7ec97e88' stroke='#3a3'>
    <circle cx='-3' cy='1' r='1.2'/>
  </g>
  <text x='-3.5' y='2.8' fill='#3a3' font-size='0.3'>disk</text>
  <g fill='#7ec97e88' stroke='#3a3'>
    <rect x='-0.8' y='-0.2' width='1.5' height='1.5'/>
    <rect x='-0.8' y='1.3' width='0.75' height='0.75'/>
  </g>
  <text x='-0.6' y='2.6' fill='#3a3' font-size='0.3'>L-shape</text>
  <g fill='#7ec97e88' stroke='#3a3'>
    <path d='M 4 1 Q 4.5 -0.3 5.5 0.5 Q 6.5 -0.2 7 1 Q 7.5 2.2 6 2.5 Q 4.8 2.5 4 1'/>
  </g>
  <text x='4.8' y='2.85' fill='#3a3' font-size='0.3'>blob</text>
  <text x='-4' y='3.6' fill='#444' font-size='0.28'>...all conformally the same as the disk.</text>
</svg>"
```

## 8.2 — Explicit examples

**Cayley transform**: upper half plane → unit disk.
$$
T(z) = \frac{z - i}{z + i}
$$
sends the real axis to the unit circle and $z = i$ to $0$.

```lean
def cayley (z : ComplexF) : ComplexF := (z - I) / (z + I)

#eval (cayley 0, abs (cayley 0))    -- (-1, 1): on the unit circle
#eval (cayley 1, abs (cayley 1))    -- on the unit circle
#eval (cayley 5, abs (cayley 5))    -- on the unit circle
#eval cayley I                       -- 0: i maps to centre
```

**Strip → upper half plane**: $w = e^z$ sends $\{0 < \mathrm{Im}\,z < \pi\}$
to $\{\mathrm{Im}\,w > 0\}$.

**Wedge → upper half plane**: $w = z^{\pi/\alpha}$.

**Disk → disk fixing 0**: rotation $z \mapsto e^{i\theta} z$.  *Only*
this, by Schwarz lemma.

## 8.3 — Sketch of the existence proof

1. Reduce to: domain $\Omega$ bounded, contains $0$, target = unit disk.
2. Family $\mathcal{F}$ of holomorphic injections $f : \Omega \to D$
   with $f(0) = 0$.
3. Find an $f$ maximising $|f'(0)|$ (Montel, normal families).
4. Show the maximiser is surjective (Blaschke factor trick).

## 8.4 — Schwarz lemma

Let $f$ be holomorphic on the disk with $f(0) = 0$ and $|f(z)| < 1$.
Then $|f(z)| \le |z|$ and $|f'(0)| \le 1$.  Equality at one interior
point forces $f$ to be a rotation.

One-line proof: $g(z) := f(z)/z$ is holomorphic, bounded by $1$ on
the boundary (max-modulus, §7.5), so bounded by $1$ everywhere.

## 8.5 — Play: a conformal grid

The Cayley map of a rectangular grid in the upper half plane:

```lean
def cayleyGrid : List (List (Float × Float)) := Id.run do
  let xs : List Float := [-2, -1, 0, 1, 2]
  let ys : List Float := [0.5, 1.0, 1.5, 2.0]
  let mut rows : List (List (Float × Float)) := []
  for y in ys do
    let mut row : List (Float × Float) := []
    for x in xs do
      let w : ComplexF := cayley ⟨x, y⟩
      row := row.concat (w.re, w.im)
    rows := rows.concat row
  pure rows

#eval cayleyGrid
-- The rectangular grid becomes a curved net inside the unit disk;
-- vertical lines become arcs through 0 (the image of i).
```

## 8.6 — Formal sketch

```lean
%load mathlib
```

```lean
example : True := by
  -- The Riemann mapping theorem is in Mathlib but its name has
  -- shifted; #findDecl "biholomorphism" 0 10
  trivial
```

## 8.7 — Prove it yourself

1. Verify $T(z) = (z-i)/(z+i)$ sends the upper half plane to the unit
   disk.  Compute $|T(z)|^2$ in terms of $\mathrm{Im}\,z$ and $|z+i|^2$.
2. Apply Schwarz to $f \circ g^{-1}$ for two biholomorphisms $f, g :
   D \to D$ with $f(0) = g(0) = 0$.  Conclude $f = g$ up to a
   rotation.
3. (Hard) Compute by Schwarz–Christoffel the explicit map from the
   upper half plane to a square.  Involves an elliptic integral.

## 8.8 — Frontier link

- **Conformal field theory**: every CFT locally pulls back to the disk.
- **Schramm–Loewner evolution (SLE)**: random conformal maps.
- **String theory**: worldsheet integrals over moduli spaces.

## What's next

Chapter 9 finds the *one* place where the conformal-equivalence story
breaks: tori.
