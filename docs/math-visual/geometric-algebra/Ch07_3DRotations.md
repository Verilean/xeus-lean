# Chapter 7 — Rotations in 3D

> *"In 3D you were taught to rotate about an axis. But rotation happens
> in a plane; the axis is just the plane's leftover perpendicular. Rotors
> name the plane directly."*

Everything from Chapters 3 and 4 carries to 3D unchanged: a rotor `R` is
a unit even element, and it acts by the same sandwich `v ↦ R v R̃`. The
only new idea is that a 3D rotor's bivector part names a **plane of
rotation** — and (Ch 5) a unit even element of `Cl(3)` is exactly a unit
**quaternion**. So this chapter is quaternion rotation, built from the
ground up, with a full 3D geometric product you can run.

## Setup

We represent a 3D multivector by its eight blade coefficients (index =
subset of `{e₁, e₂, e₃}` as a bitmask), and build the geometric product
from the blade rule — the sign is just the number of swaps to sort the
concatenated blades:

```lean
abbrev MV3 := Array Float          -- size 8, r[blade] = coefficient

/-- Sign of e_a · e_b in Cl(3,0): (−1)^(inversions between the blades). -/
def sign3 (a b : Nat) : Int := Id.run do
  let mut inv := 0
  for i in [0:3] do
    if a >>> i &&& 1 == 1 then
      for j in [0:3] do
        if b >>> j &&& 1 == 1 && j < i then inv := inv + 1
  return if inv % 2 == 0 then 1 else -1

def geo3 (A B : MV3) : MV3 := Id.run do
  let mut r : MV3 := Array.replicate 8 0.0
  for a in [0:8] do
    for b in [0:8] do
      if A[a]! != 0.0 && B[b]! != 0.0 then
        let c := a ^^^ b                     -- shared vectors square to +1 and cancel
        r := r.set! c (r[c]! + A[a]! * B[b]! * Float.ofInt (sign3 a b))
  return r

def blade (i : Nat) (v : Float := 1.0) : MV3 := (Array.replicate 8 0.0).set! i v
-- e₁=blade 1, e₂=blade 2, e₃=blade 4, e₁₂=blade 3, e₂₃=blade 6, e₃₁=blade 5

/-- Reverse R̃ negates grades 2 and 3. -/
def rev3 (A : MV3) : MV3 := Id.run do
  let mut r := A
  for i in [0:8] do
    let pc := (Nat.testBit i 0).toNat + (Nat.testBit i 1).toNat + (Nat.testBit i 2).toNat
    if pc == 2 || pc == 3 then r := r.set! i (-A[i]!)
  return r

/-- Rotor for angle θ in the e₁e₂ plane (i.e. about the e₃ axis). -/
def rotorE3 (θ : Float) : MV3 :=
  ((Array.replicate 8 0.0).set! 0 (Float.cos (θ/2))).set! 3 (-(Float.sin (θ/2)))

def rotate3 (R v : MV3) : MV3 := geo3 (geo3 R v) (rev3 R)
```

## 7.1 — The blade rule works: a quick sanity pass

Before rotating, confirm the product multiplies basis blades correctly —
`e₁e₂ = e₁₂`, `e₂e₁ = −e₁₂`, `e₁₂² = −1`:

```lean
#eval (geo3 (blade 1) (blade 2))[3]!    -- e₁e₂ coefficient on e₁₂ →  1.0
#eval (geo3 (blade 2) (blade 1))[3]!    -- e₂e₁                    → -1.0
#eval (geo3 (blade 3) (blade 3))[0]!    -- e₁₂² (scalar part)      → -1.0
```

## 7.2 — Rotating in a plane

`R = cos(θ/2) − sin(θ/2)·e₁₂` rotates in the `e₁e₂` plane. Sandwich a
vector and watch it turn — `e₁` goes to `e₂`:

<svg viewBox="-1.6 -1.6 4 3.2" width="360" style="background:#f4f4f8">
  <!-- the e1e2 plane -->
  <ellipse cx="0.9" cy="0.2" rx="1.5" ry="0.55" fill="#7ec97e33" stroke="#3a3" stroke-width="0.02"/>
  <text x="2.1" y="0.3" fill="#3a3" font-size="0.24">e₁e₂ plane</text>
  <!-- e3 axis (dual, perpendicular) -->
  <line x1="0.9" y1="0.2" x2="0.9" y2="-1.3" stroke="#888" stroke-width="0.03" stroke-dasharray="0.08 0.06"/>
  <text x="1.0" y="-1.2" fill="#888" font-size="0.24">e₃ (axis = ⋆plane)</text>
  <!-- v = e1 and R v R~ = e2, in the plane -->
  <line x1="0.9" y1="0.2" x2="2.2" y2="0.5" stroke="#c25" stroke-width="0.05"/>
  <text x="2.25" y="0.55" fill="#c25" font-size="0.26">e₁</text>
  <line x1="0.9" y1="0.2" x2="0.2" y2="-0.15" stroke="#26a" stroke-width="0.05"/>
  <text x="-0.35" y="-0.2" fill="#26a" font-size="0.26">e₂</text>
</svg>

```lean
-- rotate e₁ by 90° about e₃ (in the e₁e₂ plane) → e₂
#eval let R := rotorE3 (3.14159265/2); (rotate3 R (blade 1))[2]!   -- ≈ 1.0  (e₂)
#eval let R := rotorE3 (3.14159265/2); (rotate3 R (blade 1))[1]!   -- ≈ 0.0  (no e₁)
```

## 7.3 — Plane, not axis; quaternion, not matrix

Two things worth keeping:

- **The bivector is the plane, the axis is its dual.** A rotor names the
  `e₁e₂` plane directly (`e₁₂`); the familiar "`e₃` axis" is `⋆e₁₂`
  (Ch 6). In 4D and up there is no single axis, but rotors keep working —
  they were never about axes.
- **Composition is quaternion multiplication.** `Cl⁺(3) ≅ ℍ` (Ch 5), so
  composing rotations is multiplying rotors, which is multiplying unit
  quaternions. There is no gimbal lock (no coordinate singularity), and
  interpolating rotors gives smooth rotation (the "slerp" of graphics).
  Expanding the sandwich by hand recovers the Rodrigues rotation formula.

## 7.4 — (Optional) build your own rotor

`rotorE3` rotates in the `e₁e₂` plane. A rotor for *any* plane is
`cos(θ/2) − sin(θ/2)·B` where `B` is a unit bivector — e.g. `blade 6`
(`e₂₃`) for the `e₂e₃` plane. The sandwich code doesn't change at all.

## Exercises

1. Write `rotorE1 θ` (rotation in the `e₂e₃` plane, blade 6) and rotate
   `e₂` by 90° — you should get `e₃` (`blade 4`).
2. Compose two quarter-turns in the same plane:
   `geo3 (rotorE3 (π/2)) (rotorE3 (π/2))` and confirm its `e₁₂`
   coefficient matches `rotorE3 π` (a half-turn). Rotors compose by
   multiplication.
3. Rotate the bivector `blade 3` (`e₁₂`) with `rotorE3 θ`. Why is it
   fixed? (A rotation in a plane fixes that plane's own area element —
   the quaternion analogue of "`i` commutes with `e^{iθ}`".)
