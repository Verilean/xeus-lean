# Chapter 1 — Boosts Are Rotors

> *"A Lorentz boost is a rotation — in a plane that contains time. Give
> your rotor a timelike plane, and cos/sin turn into cosh/sinh."*

Special relativity is geometric algebra with one sign changed. In
**spacetime algebra** `Cl(1,3)` the time direction `γ₀` squares to `+1`
and the space directions `γ₁, γ₂, γ₃` to `−1`. A plane that mixes time
and space, like `γ₀γ₁`, then squares to `+1` (not `−1`), so the rotor in
that plane is built from `cosh`/`sinh` instead of `cos`/`sin` — and the
sandwich `x ↦ R x R̃` becomes a **Lorentz boost**.

## Setup

The geometric product is exactly the blade rule of GA Ch 7, plus a
**metric sign**: when two blades share a basis vector, it contributes
`γₖ² = ±1`. We work in the `γ₀,γ₁` (time, one space) plane:

```lean
def metric : Array Int := #[1, -1]            -- γ₀²=+1 (time), γ₁²=−1 (space)

/-- Sign of eₐ·e_b: (−1)^inversions × product of the shared vectors' squares. -/
def sgn (a b : Nat) : Int := Id.run do
  let mut inv := 0
  for i in [0:2] do
    if a >>> i &&& 1 == 1 then
      for j in [0:2] do
        if b >>> j &&& 1 == 1 && j < i then inv := inv + 1
  let mut m : Int := 1
  for k in [0:2] do
    if a >>> k &&& 1 == 1 && b >>> k &&& 1 == 1 then m := m * metric[k]!
  return (if inv % 2 == 0 then 1 else -1) * m

def geoS (A B : Array Float) : Array Float := Id.run do
  let mut r := Array.replicate 4 0.0     -- blades {1, γ₀, γ₁, γ₀γ₁}
  for a in [0:4] do
    for b in [0:4] do
      if A[a]! != 0.0 && B[b]! != 0.0 then
        r := r.set! (a ^^^ b) (r[(a^^^b)]! + A[a]!*B[b]!*Float.ofInt (sgn a b))
  return r

def rev (A : Array Float) : Array Float := A.set! 3 (-A[3]!)   -- reverse negates grade 2
/-- A boost of rapidity α in the γ₀γ₁ plane. -/
def boost (α : Float) : Array Float := #[Float.cosh (α/2), 0, 0, Float.sinh (α/2)]
def act (R x : Array Float) : Array Float := geoS (geoS R x) (rev R)
```

## 1.1 — The timelike plane squares to `+1`

That one fact is the whole difference from Euclidean rotation. In the
plane `e₁₂` we had `e₁₂² = −1` (circular). Here `(γ₀γ₁)² = +1`:

```lean
#eval (geoS #[0,1,0,0] #[0,1,0,0])[0]!    -- γ₀² =  1.0   (time)
#eval (geoS #[0,0,1,0] #[0,0,1,0])[0]!    -- γ₁² = -1.0   (space)
#eval (geoS #[0,0,0,1] #[0,0,0,1])[0]!    -- (γ₀γ₁)² = 1.0  ⇒ hyperbolic rotor
```

A `+1` plane exponentiates with `cosh`/`sinh`; that is why boosts are
*hyperbolic* rotations, and why nothing ever reaches the speed of light
(a hyperbola has asymptotes — the light cone).

## 1.2 — A boost is the sandwich `x ↦ R x R̃`

Boost the time axis `γ₀` (an observer at rest) by rapidity `α = 1`. The
result is `cosh α·γ₀ + sinh α·γ₁` — exactly the Lorentz transformation
`t' = γ t,  x' = γβ t` with `γ = cosh α`, `β = tanh α`:

<svg viewBox="-2.4 -2.4 4.8 4.8" width="320" style="background:#f4f4f8">
  <!-- light cone -->
  <line x1="-2.2" y1="2.2" x2="2.2" y2="-2.2" stroke="#e8b000" stroke-width="0.03"/>
  <line x1="-2.2" y1="-2.2" x2="2.2" y2="2.2" stroke="#e8b000" stroke-width="0.03"/>
  <text x="1.7" y="-1.9" fill="#e8b000" font-size="0.24">light cone</text>
  <!-- original axes t (up = -y), x (right) -->
  <line x1="0" y1="0" x2="0" y2="-2" stroke="#888" stroke-width="0.03"/>
  <line x1="0" y1="0" x2="2" y2="0" stroke="#888" stroke-width="0.03"/>
  <text x="0.1" y="-2.05" fill="#888" font-size="0.24">γ₀ (t)</text>
  <text x="2.05" y="0.2" fill="#888" font-size="0.24">γ₁ (x)</text>
  <!-- boosted t' axis: γ0 → cosh·γ0 + sinh·γ1, tilts toward the light cone -->
  <line x1="0" y1="0" x2="1.18" y2="-1.54" stroke="#c25" stroke-width="0.05"/>
  <text x="1.2" y="-1.55" fill="#c25" font-size="0.24">γ₀'</text>
  <!-- boosted x' axis: γ1 → cosh·γ1 + sinh·γ0, tilts up -->
  <line x1="0" y1="0" x2="1.54" y2="-1.18" stroke="#26a" stroke-width="0.05"/>
  <text x="1.55" y="-1.15" fill="#26a" font-size="0.24">γ₁'</text>
</svg>

```lean
#eval let R := boost 1.0; (act R #[0,1,0,0])[1]!   -- γ₀ part → cosh 1 ≈ 1.5431  (= γ)
#eval let R := boost 1.0; (act R #[0,1,0,0])[2]!   -- γ₁ part → ±sinh 1 ≈ 1.1752 (= γβ)
```

The boosted axes tilt *toward* the light cone (the yellow diagonals) but
never cross it — the hallmark of a hyperbolic rotation.

## 1.3 — Rapidity adds

The rapidity `α` (with `β = tanh α`) is the true "angle" of a boost, and
like angles, **rapidities add**: two boosts of `α₁` and `α₂` compose to
`α₁ + α₂` (multiply the rotors — `cosh`/`sinh` add via the hyperbolic
angle-sum). That is the relativistic velocity-addition law
`β = (β₁+β₂)/(1+β₁β₂)` in disguise — it is just `tanh(α₁+α₂)`.

## 1.4 — What a fast observer sees: aberration

Boost an observer and the sky bunches toward the direction of motion —
**relativistic aberration**. A star seen at angle `θ` at rest appears at
`θ'` with `cos θ' = (cos θ + β)/(1 + β cos θ)`:

<svg viewBox="-2.2 -1.6 4.4 3.2" width="360" style="background:#f4f4f8">
  <circle cx="0" cy="0" r="0.06" fill="#333"/>
  <text x="0.1" y="0.3" font-size="0.22">observer → v</text>
  <!-- rest: stars evenly around -->
  <g stroke="#bbb"><line x1="0" y1="0" x2="1.2" y2="0"/><line x1="0" y1="0" x2="0.85" y2="-0.85"/><line x1="0" y1="0" x2="0" y2="-1.2"/><line x1="0" y1="0" x2="-0.85" y2="-0.85"/><line x1="0" y1="0" x2="-1.2" y2="0"/></g>
  <!-- boosted: bunched forward (+x) -->
  <g stroke="#c25" stroke-width="0.03"><line x1="0" y1="0" x2="1.9" y2="0"/><line x1="0" y1="0" x2="1.7" y2="-0.5"/><line x1="0" y1="0" x2="1.2" y2="-0.9"/><line x1="0" y1="0" x2="0.4" y2="-1.0"/><line x1="0" y1="0" x2="-0.6" y2="-0.6"/></g>
  <text x="1.5" y="0.35" fill="#c25" font-size="0.22">forward bunching</text>
</svg>

```lean
def aberr (β θ : Float) : Float :=
  Float.acos ((Float.cos θ + β) / (1 + β * Float.cos θ))
#eval aberr 0.9 (3.14159/2)   -- a 90° star at 0.9c → ≈ 0.451 rad ≈ 26° (pulled forward)
#eval aberr 0.9 3.0           -- a nearly-behind star (172°) → ≈ 2.54 rad ≈ 146°
```

At high `β` almost the whole sky crowds into a small forward cone — the
"star-field warp" of near-light travel. This is the same boost rotor,
now acting on the *null* (light-ray) directions instead of on `γ₀`.

## Exercises

1. Boost `γ₀` by `α = 2` and read off `γ = cosh 2` and `γβ = sinh 2`.
   What speed `β = tanh 2` is that?
2. Compose two boosts: `geoS (boost 0.5) (boost 0.5)` and confirm its
   `γ₀γ₁` slot equals `(boost 1.0)`'s — rapidities added.
3. Push aberration to `β = 0.99`: at what rest-angle `θ` does a star
   appear at `θ' = 90°`? (Almost the entire sky is now in front of you.)
