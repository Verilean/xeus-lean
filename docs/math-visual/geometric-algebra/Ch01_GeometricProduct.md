# Chapter 1 — The Geometric Product

> *"The whole of geometric algebra grows from a single seed: that two
> vectors can be multiplied."*

The dot product `a·b` eats two vectors and gives a **number**. The cross
product `a×b` (in 3D only) gives a **vector**. Neither is invertible, and
neither generalises cleanly. Geometric algebra makes one move: keep
*both* pieces of information at once. The **geometric product** of two
vectors is

$$ ab = a\cdot b \;+\; a\wedge b $$

a scalar (`a·b`, the symmetric part) plus a **bivector** (`a∧b`, the
antisymmetric part — an oriented area). From this one product, rotations,
reflections, complex numbers and quaternions all fall out. This chapter
is just that first product, seen from a picture.

## Setup

For the numerical cells we use a tiny Float-backed multivector of the
2D geometric algebra `Cl(2,0)`. A multivector is
`s + a·e₁ + b·e₂ + p·e₁₂` — a scalar, two vectors, and one bivector —
with `e₁² = e₂² = 1`, `e₁e₂ = e₁₂`, `e₂e₁ = −e₁₂`.

```lean
structure MV where
  s : Float := 0
  e1 : Float := 0
  e2 : Float := 0
  e12 : Float := 0
deriving Repr

namespace MV
/-- The geometric product, expanded on the basis {1, e₁, e₂, e₁₂}. -/
def geo (X Y : MV) : MV :=
  { s   := X.s*Y.s + X.e1*Y.e1 + X.e2*Y.e2 - X.e12*Y.e12,
    e1  := X.s*Y.e1 + X.e1*Y.s - X.e2*Y.e12 + X.e12*Y.e2,
    e2  := X.s*Y.e2 + X.e2*Y.s + X.e1*Y.e12 - X.e12*Y.e1,
    e12 := X.s*Y.e12 + X.e12*Y.s + X.e1*Y.e2 - X.e2*Y.e1 }
instance : Mul MV := ⟨geo⟩

def e1v : MV := { e1 := 1 }               -- the unit vector e₁
def e2v : MV := { e2 := 1 }               -- the unit vector e₂
def vec (x y : Float) : MV := { e1 := x, e2 := y }
/-- symmetric part of two vectors = the dot product (a scalar). -/
def dot (a b : MV) : Float := a.e1*b.e1 + a.e2*b.e2
/-- antisymmetric part = the wedge (the e₁₂ coefficient — a signed area). -/
def wedge (a b : MV) : Float := a.e1*b.e2 - a.e2*b.e1
end MV
open MV
```

## 1.1 — `ab = a·b + a∧b`

Take two vectors `a` and `b`. Their geometric product splits into the
part that does not care about order (the dot product) and the part that
flips sign when you swap them (the wedge). The wedge `a∧b` is the
**oriented parallelogram** they span: its magnitude is the area, its
sign is the turning sense from `a` to `b`.

<svg viewBox="-0.5 -2.5 5 3" width="420" style="background:#f4f4f8">
  <line x1="-0.5" y1="0" x2="4.5" y2="0" stroke="#ccc"/>
  <line x1="0" y1="0.5" x2="0" y2="-2.5" stroke="#ccc"/>
  <!-- parallelogram spanned by a=(3,0) and b=(1,-1.6) (SVG y is down) -->
  <polygon points="0,0 3,0 4,-1.6 1,-1.6" fill="#7ec97e55" stroke="#3a3"/>
  <!-- a -->
  <line x1="0" y1="0" x2="3" y2="0" stroke="#c25" stroke-width="0.06"/>
  <polygon points="3,0 2.8,-0.12 2.8,0.12" fill="#c25"/>
  <text x="1.4" y="0.3" fill="#c25" font-size="0.32">a</text>
  <!-- b -->
  <line x1="0" y1="0" x2="1" y2="-1.6" stroke="#26a" stroke-width="0.06"/>
  <polygon points="1,-1.6 0.78,-1.5 1.02,-1.42" fill="#26a"/>
  <text x="0.35" y="-1.0" fill="#26a" font-size="0.32">b</text>
  <!-- orientation arc a→b -->
  <path d="M 1.2,0 A 1.2 1.2 0 0 0 0.75,-1.2" fill="none" stroke="#3a3" stroke-width="0.04"/>
  <text x="2.2" y="-0.9" fill="#3a3" font-size="0.30">a∧b</text>
</svg>

Numerically, the geometric product of two vectors lands entirely in the
scalar (`= a·b`) and the bivector (`= a∧b`) slots:

```lean
-- a = (1,0), b = (1,1):  a·b = 1,  a∧b = 1
#eval let a := vec 1 0; let b := vec 1 1; (a * b)
-- ⟨s := 1.0, e1 := 0.0, e2 := 0.0, e12 := 1.0⟩
#eval let a := vec 1 0; let b := vec 1 1; (dot a b, wedge a b)
-- (1.0, 1.0)
```

The scalar `1.0` is `a·b`; the `e12` coefficient `1.0` is `a∧b`. The two
vector slots are empty — the product of two vectors is a scalar plus a
bivector, never a vector.

## 1.2 — The bivector, and why `e₁e₂ = −e₂e₁`

The unit bivector `e₁₂ = e₁e₂` is the **oriented unit square**: sweep
`e₁` into `e₂` and you get one positive unit of area. Sweep the other
way — `e₂` into `e₁` — and you get the *same* square with the *opposite*
orientation, i.e. `−e₁₂`. Antisymmetry is not an axiom you memorise; it
is the statement "reversing the sweep reverses the sign of the area."

<svg viewBox="-1.6 -1.6 5 1.9" width="420" style="background:#f4f4f8">
  <!-- e1 e2 = +e12 : CCW sweep (drawn as CW because SVG y is down) -->
  <g>
    <polygon points="0,0 1,0 1,-1 0,-1" fill="#7ec97e55" stroke="#3a3"/>
    <line x1="0" y1="0" x2="1" y2="0" stroke="#c25" stroke-width="0.05"/>
    <line x1="0" y1="0" x2="0" y2="-1" stroke="#26a" stroke-width="0.05"/>
    <text x="0.4" y="0.25" fill="#c25" font-size="0.26">e₁</text>
    <text x="-0.45" y="-0.5" fill="#26a" font-size="0.26">e₂</text>
    <text x="0.2" y="-0.45" fill="#3a3" font-size="0.26">+e₁₂</text>
  </g>
  <!-- e2 e1 = -e12 : opposite orientation -->
  <g transform="translate(2.6,0)">
    <polygon points="0,0 1,0 1,-1 0,-1" fill="#f5a36a55" stroke="#c52"/>
    <line x1="0" y1="0" x2="0" y2="-1" stroke="#26a" stroke-width="0.05"/>
    <line x1="0" y1="0" x2="1" y2="0" stroke="#c25" stroke-width="0.05"/>
    <text x="0.4" y="0.25" fill="#c25" font-size="0.26">e₁</text>
    <text x="-0.45" y="-0.5" fill="#26a" font-size="0.26">e₂</text>
    <text x="0.2" y="-0.45" fill="#c52" font-size="0.26">−e₁₂</text>
  </g>
</svg>

```lean
#eval (e1v * e1v)     -- e₁² = 1        : ⟨1.0, 0.0, 0.0, 0.0⟩
#eval (e1v * e2v)     -- e₁e₂ = e₁₂     : ⟨0.0, 0.0, 0.0, 1.0⟩
#eval (e2v * e1v)     -- e₂e₁ = −e₁₂    : ⟨0.0, 0.0, 0.0, -1.0⟩
```

`e₁` squares to `+1` (a vector along itself has no area, all dot), while
`e₁e₂` and `e₂e₁` are pure bivectors of opposite sign.

## 1.3 — The defining relations, proven

`Float` is great for seeing numbers but cannot be reasoned about
exactly. So we restate the same algebra over `ℤ` and *prove* the three
relations that define `Cl(2,0)` — `decide` just runs the multiplication
table and checks:

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
def onei : MVi := { s := 1 }
def e1i : MVi := { e1 := 1 }
def e2i : MVi := { e2 := 1 }
def negi (X : MVi) : MVi := { s := -X.s, e1 := -X.e1, e2 := -X.e2, e12 := -X.e12 }

example : geoi e1i e1i = onei := by decide                 -- e₁² = 1
example : geoi e2i e2i = onei := by decide                 -- e₂² = 1
example : geoi e1i e2i = negi (geoi e2i e1i) := by decide  -- e₁e₂ = −e₂e₁
```

Those three lines *are* the axioms of the 2D geometric algebra; every
later fact — rotors, the link to ℂ — is a consequence. (Mathlib packages
the general construction as `CliffordAlgebra` over an arbitrary quadratic
form; we'll meet it once we need the abstract version.)

## Exercises

1. Compute `(e₁ + e₂) * (e₁ + e₂)` with `#eval`. Why is the bivector part
   zero? (Hint: what is `a∧a` for any vector `a`?)
2. A **rotor** for a quarter turn is `R = (1 − e₁₂)/√2`. Compute
   `R * e1v * R'` where `R' = (1 + e₁₂)/√2` (build them with `MV.mk` and
   `geo`), and check `e₁` rotates to `e₂`. (This is the whole of Ch 3,
   previewed.)
3. Prove over `ℤ` that `e₁₂² = −1` — i.e.
   `geoi (geoi e1i e2i) (geoi e1i e2i) = negi onei` — with `decide`. What
   familiar number system does that make the *even* part `{s + p·e₁₂}`?
