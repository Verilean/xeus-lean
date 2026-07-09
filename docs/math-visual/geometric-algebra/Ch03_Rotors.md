# Chapter 3 — Rotors: Rotation Without Matrices

> *"To rotate a vector, you do not multiply it by a matrix. You sandwich
> it between a number and its mirror."*

A rotation matrix is a table of sines and cosines you have to trust. In
geometric algebra a rotation is an **element of the algebra** — a
*rotor* `R` — applied by the **sandwich product** `v ↦ R v R̃`. The same
`R` rotates *any* object (vector, bivector, or a whole shape), rotors
compose by multiplication, and they never gimbal-lock. This is the
chapter where the geometric product pays off.

## Setup

Reuse the 2D multivector, and add the rotor, the reverse `R̃`, and the
sandwich:

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
def vec (x y : Float) : MV := { e1 := x, e2 := y }

/-- A rotor for a rotation by θ in the e₁e₂ plane:  R = e^(−e₁₂ θ/2). -/
def rotor (θ : Float) : MV := { s := Float.cos (θ/2), e12 := -(Float.sin (θ/2)) }
/-- The reverse R̃ flips the sign of the bivector part. -/
def reverse (M : MV) : MV := { s := M.s, e1 := M.e1, e2 := M.e2, e12 := -M.e12 }
/-- Apply a rotor by the sandwich product. -/
def rotate (R v : MV) : MV := R * v * reverse R
end MV
open MV
```

## 3.1 — The rotor lives in the even subalgebra (which *is* ℂ)

Because `e₁₂² = −1` (Ch 1 exercise 3), the *even* part of the algebra —
elements `s + p·e₁₂` — behaves exactly like the complex numbers, with
`e₁₂` playing the role of `i`. A **rotor** is a unit even element:

$$ R = \cos\tfrac{\theta}{2} - \sin\tfrac{\theta}{2}\,e_{12}
     = e^{-e_{12}\,\theta/2} $$

— literally `e^{iθ/2}` in disguise. That is why exponentiating a
bivector rotates: it is Euler's formula, one dimension up.

## 3.2 — The sandwich `v ↦ R v R̃`

To rotate a vector `v`, multiply `R v R̃`. The two half-angle rotors on
either side combine to a full rotation of `θ`:

<svg viewBox="-2.4 -2.4 4.8 4.8" width="360" style="background:#f4f4f8">
  <line x1="-2.4" y1="0" x2="2.4" y2="0" stroke="#ccc"/>
  <line x1="0" y1="-2.4" x2="0" y2="2.4" stroke="#ccc"/>
  <!-- v = e1 -->
  <line x1="0" y1="0" x2="2" y2="0" stroke="#c25" stroke-width="0.06"/>
  <polygon points="2,0 1.8,-0.12 1.8,0.12" fill="#c25"/>
  <text x="2.1" y="0.3" fill="#c25" font-size="0.3">v</text>
  <!-- R v R~ = e2 (rotated 90°, drawn up = -y in SVG) -->
  <line x1="0" y1="0" x2="0" y2="-2" stroke="#26a" stroke-width="0.06"/>
  <polygon points="0,-2 -0.12,-1.8 0.12,-1.8" fill="#26a"/>
  <text x="0.15" y="-2.05" fill="#26a" font-size="0.3">R v R̃</text>
  <!-- rotation arc -->
  <path d="M 1.4,0 A 1.4 1.4 0 0 0 0,-1.4" fill="none" stroke="#3a3" stroke-width="0.04"/>
  <text x="1.15" y="-1.1" fill="#3a3" font-size="0.28">θ</text>
</svg>

```lean
-- rotate e₁ by 90°  → e₂
#eval let R := rotor (3.14159265358979/2); rotate R (vec 1 0)
-- ⟨s := 0.0, e1 := 0.0, e2 := 1.0, e12 := 0.0⟩

-- rotate e₁ by 180° → −e₁
#eval let R := rotor 3.14159265358979; rotate R (vec 1 0)
-- ⟨…, e1 := -1.0, …⟩
```

The output stays a pure vector (grades `e1`, `e2` only) — the sandwich
*preserves grade*, so it maps vectors to vectors, which a bare `R v`
would not.

## 3.3 — Why the half-angle?

The `θ/2` is not a fudge. A rotor is built from **two reflections**
(Ch 4), and reflecting twice through planes at angle `θ/2` rotates by
`θ`. The visible consequence: `R` and `−R` give the *same* rotation
(`(−R) v (−R̃) = R v R̃`), so the rotors *double-cover* the rotations —
the same 2-to-1 relationship as unit complex numbers `e^{iθ/2}` turning
the plane, and (in 3D, Ch 7) unit quaternions turning space.

## 3.4 — Formal: the reverse, and unit rotors

The reverse is what makes the sandwich an *inverse* on both sides. It is
an **involution** (`R̃̃ = R`), which we can prove exactly over `ℤ`, and it
leaves vectors (grade 1) untouched:

```lean
structure MVi where
  s : Int := 0
  e1 : Int := 0
  e2 : Int := 0
  e12 : Int := 0
deriving Repr, DecidableEq

def reversei (M : MVi) : MVi := { M with e12 := -M.e12 }

-- reversing twice is the identity
example (M : MVi) : reversei (reversei M) = M := by simp [reversei]
-- reverse fixes vectors (they carry no bivector part)
example : reversei { e1 := 3, e2 := 5 } = { e1 := 3, e2 := 5 } := by decide
```

For a *unit* rotor `R = cos(θ/2) − sin(θ/2)·e₁₂` we have `R R̃ = cos² +
sin² = 1`, so `R̃ = R⁻¹` and the sandwich really is a rotation — check it
numerically:

```lean
#eval let R := rotor (3.14159265358979/2); (R * reverse R)
-- ⟨s := 1.0, …⟩  =  R R̃ = 1
```

## Exercises

1. Compose two rotors: `rotor (π/4) * rotor (π/4)` and confirm it equals
   `rotor (π/2)` (compare components). Rotations *add* by *multiplying*
   rotors.
2. Rotate the bivector `e₁₂` itself: `rotate (rotor θ) { e12 := 1 }`. Why
   is it unchanged for every `θ`? (What does a rotation in the plane do
   to the plane's own area element?)
3. Show numerically that `−R` gives the same rotation as `R`: build
   `negR := { s := -R.s, e12 := -R.e12 }` for `R = rotor (π/3)` and check
   `rotate negR (vec 1 0) = rotate R (vec 1 0)`.
