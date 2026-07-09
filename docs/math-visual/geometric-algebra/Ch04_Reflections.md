# Chapter 4 — Reflections, and Why Two Make a Rotation

> *"Every rotation is two reflections. That is not a theorem you prove;
> it is what a rotation* is."

Reflection is the most primitive rigid motion — a mirror. In geometric
algebra reflecting a vector `v` in the line along a unit vector `n` is
just another sandwich: `v ↦ n v n`. The payoff of this chapter is the
fact that powered Chapter 3: **compose two reflections and you get a
rotation**, by *twice* the angle between the mirrors. That is where the
rotor — and its half-angle — actually comes from.

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
def vec (x y : Float) : MV := { e1 := x, e2 := y }
/-- The unit vector at angle θ. -/
def unit (θ : Float) : MV := { e1 := Float.cos θ, e2 := Float.sin θ }
/-- Reflect `v` in the line along unit vector `n`:  v ↦ n v n. -/
def reflect (n v : MV) : MV := n * v * n
end MV
open MV
```

## 4.1 — A reflection is a sandwich `v ↦ n v n`

Reflecting in the line along a unit vector `n` keeps the component of
`v` along `n` and flips the perpendicular one:

<svg viewBox="-2.4 -1.8 4.8 3.4" width="380" style="background:#f4f4f8">
  <!-- mirror line = x-axis (n = e1) -->
  <line x1="-2.3" y1="0" x2="2.3" y2="0" stroke="#888" stroke-width="0.03" stroke-dasharray="0.1 0.08"/>
  <text x="2.0" y="0.3" fill="#888" font-size="0.28">n</text>
  <!-- v -->
  <line x1="0" y1="0" x2="1.4" y2="-1.1" stroke="#c25" stroke-width="0.06"/>
  <polygon points="1.4,-1.1 1.2,-1.02 1.32,-0.9" fill="#c25"/>
  <text x="1.5" y="-1.15" fill="#c25" font-size="0.3">v</text>
  <!-- n v n : reflected across x-axis -->
  <line x1="0" y1="0" x2="1.4" y2="1.1" stroke="#26a" stroke-width="0.06"/>
  <polygon points="1.4,1.1 1.2,1.02 1.32,0.9" fill="#26a"/>
  <text x="1.5" y="1.25" fill="#26a" font-size="0.3">n v n</text>
</svg>

```lean
#eval reflect (vec 1 0) (vec 0 1)   -- reflect e₂ in the x-axis → −e₂
-- ⟨…, e2 := -1.0, …⟩
#eval reflect (unit 0.7853981) (vec 1 0)  -- reflect e₁ in the 45° line → e₂
-- ⟨…, e2 := 1.0, …⟩  (up to float noise in e1)
```

## 4.2 — Two reflections = a rotation by twice the angle

Reflect in the line `n₁`, then in the line `n₂`. The two mirrors sit at
some angle `φ` apart, and the composition is a **rotation by `2φ`**:

<svg viewBox="-2.4 -2.4 4.8 4.8" width="360" style="background:#f4f4f8">
  <!-- mirror 1: x-axis -->
  <line x1="-2.2" y1="0" x2="2.2" y2="0" stroke="#888" stroke-dasharray="0.1 0.08" stroke-width="0.03"/>
  <text x="2.0" y="0.3" fill="#888" font-size="0.26">n₁</text>
  <!-- mirror 2: 45° line (drawn at -45° since SVG y is down) -->
  <line x1="-1.6" y1="1.6" x2="1.6" y2="-1.6" stroke="#888" stroke-dasharray="0.1 0.08" stroke-width="0.03"/>
  <text x="1.5" y="-1.55" fill="#888" font-size="0.26">n₂</text>
  <!-- v = e1 -->
  <line x1="0" y1="0" x2="1.8" y2="0" stroke="#c25" stroke-width="0.06"/>
  <text x="1.9" y="0.28" fill="#c25" font-size="0.28">v</text>
  <!-- result = e2 (90° = 2·45°), drawn up -->
  <line x1="0" y1="0" x2="0" y2="-1.8" stroke="#26a" stroke-width="0.06"/>
  <text x="0.1" y="-1.85" fill="#26a" font-size="0.28">n₂n₁ · v</text>
  <path d="M 1.2,0 A 1.2 1.2 0 0 0 0,-1.2" fill="none" stroke="#3a3" stroke-width="0.04"/>
  <text x="1.05" y="-0.95" fill="#3a3" font-size="0.26">2φ</text>
</svg>

```lean
-- reflect e₁ in the x-axis (φ=0 apart), then in the 45° line: rotates 90°
#eval reflect (unit 0.7853981) (reflect (vec 1 0) (vec 1 0))
-- ⟨…, e2 := 1.0, …⟩  = e₂

-- and the rotor of Ch 3 is *literally* the product of the two mirrors:
#eval (unit 0.7853981) * (vec 1 0)
-- ⟨s := 0.707…, e12 := -0.707…⟩  = rotor(90°)
```

`R = n₂ n₁` — a rotor is *by definition* the product of two unit
vectors, and `R̃ = n₁ n₂`, so the two-reflection sandwich
`n₂ (n₁ v n₁) n₂` is exactly `R v R̃`.

## 4.3 — So *that* is the half-angle

This closes the loop with §3.3. The mirrors are `φ` apart, the rotation
is `2φ`, and `R = n₂ n₁` carries the *half*-angle `φ`. Nothing was
fudged: the `θ/2` in `R = cos(θ/2) − sin(θ/2)·e₁₂` is the angle between
the two mirrors whose product `R` is.

## 4.4 — Formal: reflecting twice is the identity

A mirror is its own inverse. With a unit vector `n` (so `n² = 1`),
reflecting twice returns the original — provable exactly over `ℤ`:

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
def reflecti (n v : MVi) : MVi := geoi (geoi n v) n

-- reflecting a vector twice in the same (unit) line e₁ returns it
example : reflecti { e1 := 1 } (reflecti { e1 := 1 } { e1 := 3, e2 := 5 })
        = { e1 := 3, e2 := 5 } := by decide
```

## Exercises

1. Reflect the *same* `v = vec 1 1` in `n₁ = e₁` and then in `n₂ = e₂`
   (`φ = 90°`). What rotation do you get? (Predict `2φ = 180°`, then
   check with `reflect`.)
2. Show numerically that reflection preserves length: for `v = vec 3 4`
   and `n = unit 1.0`, the reflected vector has the same `e1²+e2²`.
3. In 3D, reflection in a *plane* with unit normal `n` is
   `v ↦ −n v n`. Why the extra minus sign there but not here? (Hint:
   count how many perpendicular directions the mirror flips.)
