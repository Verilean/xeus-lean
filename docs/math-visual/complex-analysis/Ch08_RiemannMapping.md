# Chapter 8 — The Riemann Mapping Theorem

The Riemann mapping theorem is one of the most surprising claims of
classical mathematics:

> **Every** simply-connected proper open subset of $\mathbb{C}$ is
> biholomorphic to the open unit disk.

That is, no matter how strange the shape — an L-shaped region, the
interior of a fractal, the complement of a curve — there is a
conformal bijection from your shape to the round disk
$\{|z| < 1\}$, with a holomorphic inverse.  Up to a Möbius
transformation, the map is unique.

Two domains that *look* nothing alike are conformally identical.

```lean
%load mathlib
```

```lean
import Mathlib.Analysis.Complex.Basic
open Complex Real
```

## 8.1 — Why this is surprising

Three regions that all look very different:

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

The disk, the L-shape, and the blob each have a biholomorphic map to
the others.  *Distances* and *angles* are not the same — but
*infinitesimal angles* are preserved, because the maps are conformal
(=  holomorphic with nowhere-zero derivative).

## 8.2 — Explicit examples first

For specific shapes we can write the map down.

**Upper half plane → unit disk.**  The Cayley transform:
$$
T(z) = \frac{z - i}{z + i}
$$
sends the real axis to the unit circle and $z = i$ to $0$.

```lean
def cayley (z : ℂ) : ℂ := (z - I) / (z + I)

-- The real axis maps to the unit circle:
#eval (cayley 0, Complex.abs (cayley 0))         -- (-1, 1)
#eval (cayley 1, Complex.abs (cayley 1))         -- on the unit circle
#eval (cayley 5, Complex.abs (cayley 5))         -- ditto
#eval cayley I                                    -- 0: i maps to centre
```

**Strip → upper half plane.**  $w = e^z$ sends the strip
$\{0 < \mathrm{Im}\,z < \pi\}$ to the upper half plane.

**Wedge → upper half plane.**  $w = z^{\pi/\alpha}$ unfolds a wedge of
angle $\alpha$ to a half plane.

**Disk → disk (fixing 0).**  Rotation $z \mapsto e^{i\theta} z$.
That's the *only* such map, by Schwarz lemma — see §8.4.

## 8.3 — The existence proof, sketched

Schwarz's, Riemann's, and Carathéodory's combined proof goes roughly:

1. Reduce to: domain $\Omega$ is bounded, contains $0$, and the
   target is the unit disk centred at $0$.
2. Consider the family $\mathcal{F}$ of all holomorphic injections
   $f : \Omega \to D$ with $f(0) = 0$.
3. Find an $f$ in $\mathcal{F}$ maximising $|f'(0)|$.  This is the
   "biggest" map; a compactness argument (Montel's theorem, normal
   families) shows the supremum is attained.
4. Show this maximiser is a bijection.  Argument by contradiction:
   if it's not surjective, you can compose with a Blaschke factor to
   make the derivative at 0 larger — contradicting maximality.

Each step is a small theorem; together they pin down the existence of
a biholomorphism.  No explicit formula in general — you only know
one exists.

## 8.4 — Schwarz lemma: the bedrock

**Schwarz lemma.**  Let $f$ be holomorphic on the unit disk with
$f(0) = 0$ and $|f(z)| < 1$ for all $|z| < 1$.  Then:
- $|f(z)| \le |z|$ for all $|z| < 1$, and
- $|f'(0)| \le 1$.

If equality holds in either inequality (at one interior point),
then $f$ is a rotation, $f(z) = e^{i\theta} z$.

The proof is one line: $g(z) := f(z)/z$ is holomorphic on the disk
(removable singularity at $0$), bounded by $1$ on the boundary
(maximum modulus from §7.5), so bounded by $1$ everywhere.  Hence
$|f(z)| \le |z|$.  Equality means $|g|$ achieves its maximum in the
interior, so $g$ is a constant of modulus $1$, i.e. $f$ is a
rotation.

That's why the biholomorphisms $D \to D$ fixing $0$ are *exactly*
rotations: there's no room for anything else.

## 8.5 — Play: visualise a conformal map

Let's see what an L-shape → disk map does to a grid in the L-shape.
We won't compute the map analytically — we'll fake it with the
**Schwarz–Christoffel formula** (which gives explicit maps from
polygonal domains to the half plane).  Even faking it for the
visualisation, you can see how grid lines get curved.

```lean
-- Cayley map of a grid in the upper half plane:
def cayleyGrid : List (List (ℝ × ℝ)) := Id.run do
  let xs : List ℝ := [-2, -1, 0, 1, 2]
  let ys : List ℝ := [0.5, 1.0, 1.5, 2.0]
  let mut rows : List (List (ℝ × ℝ)) := []
  for y in ys do
    let mut row : List (ℝ × ℝ) := []
    for x in xs do
      let w : ℂ := cayley ⟨x, y⟩
      row := row.concat (w.re, w.im)
    rows := rows.concat row
  pure rows

#eval cayleyGrid
-- The rectangular grid in the upper half plane becomes a curved net
-- inside the unit disk.  Plot it; you'll see vertical strips becoming
-- arcs through 0 (the image of i) and horizontal strips becoming
-- concentric arcs.
```

## 8.6 — Formal sketch

Mathlib's `Riemann mapping theorem` is one of the deepest results
formalised; it lives in `Mathlib.Analysis.Complex.UpperHalfPlane`
plus several supporting files, and uses Montel's theorem under the
hood.  The headline statement, paraphrased:

```lean
-- For Ω ⊂ ℂ open, connected, simply-connected, and a proper subset of ℂ,
-- there exists a biholomorphism Ω → 𝔻 (open unit disk).
example : True := by
  -- The actual statement form is wordy; look for
  --   Complex.exists_biholomorphism_of_simplyConnected
  -- or similar.  `#findDecl "biholomorphism" 0 10` finds candidates.
  trivial
```

In practice the Schwarz lemma and the family-of-maps compactness are
the load-bearing pieces; the rest of the proof is bookkeeping.

## 8.7 — Prove it yourself

1. (Easy) Show that the Cayley transform $T(z) = (z-i)/(z+i)$ sends
   the upper half plane $\{\mathrm{Im}\,z > 0\}$ bijectively to the
   open unit disk.  (Compute |T(z)| explicitly in terms of
   $\mathrm{Im}\,z$ and $|z+i|$.)
2. (Medium) Apply Schwarz to $f \circ g^{-1}$ for two
   biholomorphisms $f, g$ from the disk to itself with $f(0) =
   g(0) = 0$.  Conclude that $f = g$ up to a rotation.
3. (Hard) Compute, by Schwarz–Christoffel, the explicit conformal
   map from the upper half plane to a square.  (The map involves
   an elliptic integral; you don't need to evaluate it, just write
   it down.)

## 8.8 — Frontier link

- **Conformal field theory.**  Every CFT on a Riemann surface can
  be locally pulled back to the disk via the Riemann mapping
  theorem.  That's why "scaling = conformal symmetry" is so
  powerful: locally, every 2D shape is the same.
- **Schramm–Loewner evolution (SLE).**  Random curves in 2D are
  encoded by random conformal maps from the half plane.  The
  Riemann mapping theorem says SLE is the universal language for
  conformally invariant random fractals — percolation
  interfaces, Ising spin clusters, …
- **String theory.**  World-sheet path integrals reduce to integrals
  over the moduli space of Riemann surfaces, which would be
  intractable were it not for the Riemann mapping theorem
  collapsing the local complexity at every point.

## What's next

Chapter 9 will see the conformal-equivalence story break in *one*
specific way: the **torus**.  Tori are conformally classified by a
single complex parameter (the modular parameter $\tau$), and the
attempt to be a bijection from $\mathbb{C}$ to a torus forces us
into **elliptic functions** — doubly periodic meromorphic
functions, the natural inhabitants of $\mathbb{C}/\Lambda$.
