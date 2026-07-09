# Chapter 2 — Black Holes Bend Light

> *"Near a black hole, straight lines are the ones the light takes. What
> looks bent is the space; what looks distorted is the sky behind."*

Mass curves spacetime, and light follows the straightest available path
(a null geodesic) through the curve. Far away this is a gentle bend; near
a black hole it is extreme enough that light can *orbit*, that a region
of the sky goes *black* (the shadow), and that everything behind the hole
is smeared into rings and arcs. This chapter computes that distortion.
(In geometric algebra, these geodesics come from **Gauge Theory
Gravity** — Schwarzschild in flat spacetime algebra — but the deflection
formulas below are the standard GR ones GTG reproduces.)

## Setup

We measure everything in Schwarzschild radii, `Rs = 2GM/c² = 1`.

```lean
def Rs : Float := 1.0
/-- The photon sphere: the radius where light can orbit (unstably). -/
def photonSphere : Float := 1.5 * Rs
/-- The shadow's edge = critical impact parameter b_c = (3√3/2) Rs. -/
def shadowB : Float := (3.0 * Float.sqrt 3.0 / 2.0) * Rs
/-- Weak-field light deflection for a ray of impact parameter b:  α ≈ 2Rs/b. -/
def deflectWeak (b : Float) : Float := 2.0 * Rs / b
/-- Strong field: the deflection diverges logarithmically as b → b_c. -/
def deflectStrong (b : Float) : Float := -(Float.log (b / shadowB - 1.0)) + 0.9
```

## 2.1 — Light bends (Eddington, 1919)

A ray grazing a mass at impact parameter `b` is deflected by `α ≈ 2Rs/b`
(twice the Newtonian value — the confirmation that made Einstein famous):

<svg viewBox="-3 -1.4 6 2.8" width="440" style="background:#f4f4f8">
  <circle cx="0" cy="0" r="0.35" fill="#333"/>
  <text x="0" y="0.05" fill="#fff" font-size="0.22" text-anchor="middle">M</text>
  <!-- incoming ray, bent slightly downward past the mass -->
  <path d="M -2.9,-0.8 Q 0,-0.75 2.9,-0.35" fill="none" stroke="#e8b000" stroke-width="0.04"/>
  <line x1="-2.9" y1="-0.8" x2="-2.9" y2="-0.35" stroke="#bbb" stroke-dasharray="0.06 0.05" stroke-width="0.02"/>
  <text x="-2.85" y="-0.55" fill="#bbb" font-size="0.2">b</text>
  <text x="2.3" y="-0.55" fill="#c25" font-size="0.22">α (bend)</text>
</svg>

```lean
#eval deflectWeak 10.0    -- distant ray (b = 10 Rs): 0.2 rad — a gentle bend
#eval deflectWeak 3.0     -- closer (b = 3 Rs): 0.67 rad — already large
```

## 2.2 — The photon sphere and the photon ring

Come closer and the bend runs away. At `r = 1.5 Rs` light *orbits* the
hole (the **photon sphere**); for rays approaching the **critical impact
parameter** `b_c = (3√3/2)Rs ≈ 2.598`, the deflection diverges — a ray
can loop the hole once, twice, any number of times before escaping. Each
extra loop paints another, thinner **photon ring**:

<svg viewBox="-2.2 -2.2 4.4 4.4" width="300" style="background:#f4f4f8">
  <circle cx="0" cy="0" r="0.6" fill="#111"/>
  <circle cx="0" cy="0" r="1.55" fill="none" stroke="#888" stroke-width="0.02" stroke-dasharray="0.08 0.06"/>
  <text x="0.05" y="1.85" fill="#888" font-size="0.22" text-anchor="middle">photon sphere 1.5Rs</text>
  <!-- a ray looping the hole -->
  <path d="M -2.1,0.9 Q -0.9,0.9 -0.55,0.35 A 0.75 0.75 0 1 1 0.35,-0.55 Q 0.9,-0.9 2.1,-0.6" fill="none" stroke="#e8b000" stroke-width="0.04"/>
</svg>

```lean
#eval photonSphere            -- 1.5   (the orbiting radius)
#eval shadowB                 -- 2.598 (the ring / shadow edge)
#eval deflectStrong 2.7       -- b just outside b_c: 4.14 rad — light loops past π
#eval deflectStrong 2.61      -- nearer b_c: 6.28 rad ≈ 2π — a full loop → the ring
```

## 2.3 — The shadow and the lensed sky

Any ray aimed with `b < b_c` spirals in and never comes back, so the
observer sees a black disk — the **shadow**, of angular radius set by
`b_c ≈ 2.6 Rs` (larger than the hole itself: gravity magnifies it). Just
outside sits the bright **photon ring**, and the whole background sky is
lensed — a star directly behind the hole smears into a complete
**Einstein ring**; off-axis stars split into arcs:

<svg viewBox="-2.4 -2.4 4.8 4.8" width="340" style="background:#05060a">
  <!-- background stars (a few) -->
  <g fill="#ccd">
    <circle cx="-1.9" cy="-1.5" r="0.03"/><circle cx="1.6" cy="-1.9" r="0.03"/>
    <circle cx="2.0" cy="1.2" r="0.03"/><circle cx="-1.4" cy="1.8" r="0.03"/>
    <circle cx="0.3" cy="-2.1" r="0.03"/><circle cx="-2.1" cy="0.5" r="0.03"/>
  </g>
  <!-- Einstein ring: a background star directly behind, smeared into a ring -->
  <circle cx="0" cy="0" r="1.35" fill="none" stroke="#9db8ff" stroke-width="0.05" opacity="0.85"/>
  <!-- lensed arcs of off-axis stars -->
  <path d="M 1.1,-1.1 A 1.55 1.55 0 0 1 1.55,-0.2" fill="none" stroke="#c9d6ff" stroke-width="0.04"/>
  <path d="M -1.2,1.0 A 1.55 1.55 0 0 1 -1.5,0.3" fill="none" stroke="#c9d6ff" stroke-width="0.04"/>
  <!-- photon ring (bright, thin) -->
  <circle cx="0" cy="0" r="0.92" fill="none" stroke="#ffcf6b" stroke-width="0.06"/>
  <!-- the shadow -->
  <circle cx="0" cy="0" r="0.85" fill="#000"/>
  <text x="0" y="2.15" fill="#9db8ff" font-size="0.2" text-anchor="middle">Einstein ring</text>
  <text x="0" y="0.06" fill="#555" font-size="0.18" text-anchor="middle">shadow</text>
</svg>

The bright orange ring is the light that looped the hole; the blue ring
is the lensed image of the sky behind it. This is the distortion the
Event Horizon Telescope photographed, and what a ray-tracer produces by
shooting one null geodesic per pixel and reading where it came from.

## 2.4 — Where geometric algebra comes in

The deflection above is standard Schwarzschild. Geometric algebra earns
its place at the *rendering* step: in **Gauge Theory Gravity** the metric
is replaced by gauge fields on flat spacetime algebra, so a photon's path
is a rotor-valued ODE in the same `Cl(1,3)` of Chapter 1 — no tensor
index gymnastics, and the boost that carries the observer's velocity
(Ch 1) composes with the lensing in the *same* algebra. Aberration
(a moving camera) and lensing (a curving spacetime) become one pipeline.

## Exercises

1. How much bigger is the shadow than the horizon? Compare `shadowB`
   with `Rs`. (The sky sees a disk ~2.6× the hole's radius.)
2. Find the impact parameter `b` for which `deflectWeak b = π` (a ray
   bent straight back). Is it inside or outside `b_c`? What does that
   tell you about when the weak-field formula stops being valid?
3. The Einstein-ring radius scales as `√Rs` (for a source and observer at
   fixed distances). Doubling the black hole's mass multiplies the ring
   radius by what factor?
