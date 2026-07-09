# Chapter 5 — ℂ and ℍ Are Hiding Inside

> *"The complex numbers are not a starting point. They are the even part
> of the plane's geometric algebra — and the quaternions are the even
> part of space's."*

Complex numbers and quaternions are usually introduced as inventions:
"adjoin an `i` with `i² = −1`," "adjoin `i, j, k`." Geometric algebra
says they were there all along — as the **even subalgebras**. `Cl⁺(2)`
(scalars + bivectors of the plane) *is* ℂ; `Cl⁺(3)` *is* the
quaternions ℍ. This chapter makes the first isomorphism concrete and
sketches the second. It is the bridge back to the
[Complex Analysis](../complex-analysis/README.md) track.

## Setup

```lean
structure MV where
  s : Float := 0
  e1 : Float := 0
  e2 : Float := 0
  e12 : Float := 0
deriving Repr

namespace MV
def geo (X Y : MV) : MV :=
  { s   := X.s*Y.s + X.e1*Y.e1 + X.e2*Y.e2 - X.e12*Y.e12,
    e1  := X.s*Y.e1 + X.e1*Y.s - X.e2*Y.e12 + X.e12*Y.e2,
    e2  := X.s*Y.e2 + X.e2*Y.s + X.e1*Y.e12 - X.e12*Y.e1,
    e12 := X.s*Y.e12 + X.e12*Y.s + X.e1*Y.e2 - X.e2*Y.e1 }
instance : Mul MV := ⟨geo⟩
/-- Embed the complex number a + b·i as the even element a + b·e₁₂. -/
def cpx (a b : Float) : MV := { s := a, e12 := b }
end MV
open MV
```

## 5.1 — `Cl⁺(2) ≅ ℂ`, with `e₁₂` as `i`

The even elements `s + p·e₁₂` are closed under the geometric product
(even × even = even), and `e₁₂² = −1`. So the map `a + b·i ↦ a + b·e₁₂`
sends complex multiplication to the geometric product — exactly:

<svg viewBox="-2.2 -2.2 4.4 4.4" width="320" style="background:#f4f4f8">
  <line x1="-2.1" y1="0" x2="2.1" y2="0" stroke="#ccc"/>
  <line x1="0" y1="-2.1" x2="0" y2="2.1" stroke="#ccc"/>
  <text x="1.9" y="0.35" fill="#888" font-size="0.26">1 (scalar)</text>
  <text x="0.12" y="-1.85" fill="#888" font-size="0.26">e₁₂ (= i)</text>
  <!-- z = 1 + i -->
  <line x1="0" y1="0" x2="1" y2="-1" stroke="#c25" stroke-width="0.06"/>
  <polygon points="1,-1 0.8,-0.92 0.92,-0.8" fill="#c25"/>
  <text x="1.05" y="-1.05" fill="#c25" font-size="0.3">1 + e₁₂</text>
  <!-- (1+i)² = 2i -->
  <line x1="0" y1="0" x2="0" y2="-2" stroke="#26a" stroke-width="0.06"/>
  <text x="0.12" y="-2.05" fill="#26a" font-size="0.28">2 e₁₂</text>
</svg>

```lean
#eval cpx 1 1 * cpx 1 1     -- (1+i)² = 2i   → ⟨s := 0.0, …, e12 := 2.0⟩
#eval cpx 0 1 * cpx 0 1     -- i·i   = −1    → ⟨s := -1.0, …⟩
#eval cpx 3 4 * cpx 1 (-2)  -- (3+4i)(1−2i) = 11 − 2i → ⟨s := 11.0, e12 := -2.0⟩
```

So a rotor in the plane (Ch 3) is literally a *unit complex number*
`e^{iθ/2}` — which is why "multiply by a unit complex number to rotate"
(the Complex Analysis track, Ch 1) and "sandwich with a rotor" are the
same operation seen from two heights.

## 5.2 — The isomorphism, proven

Over `ℤ` we can prove that the even-subalgebra product reproduces the
complex-multiplication formula `(a+bi)(c+di) = (ac−bd) + (ad+bc)i`
exactly — not for examples, but for all `a, b, c, d`:

```lean
structure MVi where
  s : Int := 0
  e1 : Int := 0
  e2 : Int := 0
  e12 : Int := 0
deriving Repr, DecidableEq

def geoi (X Y : MVi) : MVi :=
  { s   := X.s*Y.s + X.e1*Y.e1 + X.e2*Y.e2 - X.e12*Y.e12,
    e1  := X.s*Y.e1 + X.e1*Y.s - X.e2*Y.e12 + X.e12*Y.e2,
    e2  := X.s*Y.e2 + X.e2*Y.s + X.e1*Y.e12 - X.e12*Y.e1,
    e12 := X.s*Y.e12 + X.e12*Y.s + X.e1*Y.e2 - X.e2*Y.e1 }

example (a b c d : Int) :
    geoi { s := a, e12 := b } { s := c, e12 := d }
      = { s := a*c - b*d, e12 := a*d + b*c } := by
  simp [geoi]
```

That `s`/`e₁₂` pair is the real/imaginary part of the complex product,
and the two vector slots stay zero — the even part is a genuine
subalgebra.

## 5.3 — `Cl⁺(3) ≅ ℍ`: the quaternions

Go up one dimension. Space has three basis vectors `e₁, e₂, e₃` and
therefore three **bivectors**: `e₂₃, e₃₁, e₁₂`. Each squares to `−1`,
and — with the convention

$$ i = e_{23},\quad j = e_{31},\quad k = e_{12} $$

they satisfy Hamilton's relations `i² = j² = k² = ijk = −1` on the nose.
So the even subalgebra of 3D geometric algebra — scalars plus these
three bivectors — *is* the quaternions ℍ. A 3D rotor is a **unit
quaternion**, and the sandwich `v ↦ R v R̃` is quaternion rotation,
recovered without ever "adjoining" anything. (We build 3D rotors out in
Ch 7.)

| dimension | even subalgebra | a rotor is a… |
|---|---|---|
| plane (2D) | `Cl⁺(2) ≅ ℂ` | unit complex number `e^{iθ/2}` |
| space (3D) | `Cl⁺(3) ≅ ℍ` | unit quaternion |

## Exercises

1. Verify `cpx a b * cpx c d` matches `(a+bi)(c+di)` for your own choice
   of `a, b, c, d` (compute the complex product by hand, then `#eval`).
2. The complex conjugate `a − bi` is the *reverse* of `a + b·e₁₂`. Check
   that `cpx a b * (reverse of it)` is `a² + b²` (a real scalar) — the
   squared modulus. (Reuse `reverse` from Ch 3.)
3. Using the relations in §5.3, compute `e₂₃ · e₃₁` and confirm it is
   `e₁₂` (i.e. `i·j = k`). This is why 3D rotors multiply like
   quaternions.
