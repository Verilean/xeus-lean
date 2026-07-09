# Chapter 2 — The Outer Product and Grades

> *"A vector is a directed length; a bivector is a directed area. The
> outer product is the machine that turns the first into the second."*

Chapter 1 split the geometric product into `a·b + a∧b`. The dot part
*lowers* dimension (two vectors → a number); the wedge part *raises* it
(two vectors → an oriented plane). That raising is the **outer product**,
and iterating it organises a multivector into **grades**: scalars
(grade 0), vectors (grade 1), bivectors (grade 2), and — in higher
dimensions — up. This chapter is about that graded structure.

## Setup

We reuse the 2D multivector from Chapter 1, and add the outer product
and grade projections. Re-paste it here so the cells run:

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
/-- Outer product of two vectors → a pure bivector (the e₁₂ slot). -/
def wedge (a b : MV) : MV := { e12 := a.e1 * b.e2 - a.e2 * b.e1 }
/-- Grade projections ⟨M⟩₀, ⟨M⟩₁, ⟨M⟩₂. -/
def gr0 (M : MV) : MV := { s := M.s }
def gr1 (M : MV) : MV := { e1 := M.e1, e2 := M.e2 }
def gr2 (M : MV) : MV := { e12 := M.e12 }
end MV
open MV
```

## 2.1 — Grades: scalar, vector, bivector

A general 2D multivector `s + a·e₁ + b·e₂ + p·e₁₂` is a sum of three
**grades** — a number, an arrow, and an oriented area — that live in the
same object but never mix:

<svg viewBox="0 0 480 130" width="480" style="background:#f4f4f8">
  <!-- grade 0: a point/scalar -->
  <circle cx="60" cy="70" r="5" fill="#3a3"/>
  <text x="60" y="105" text-anchor="middle" font-size="13">grade 0 — scalar</text>
  <text x="60" y="30" text-anchor="middle" font-size="12" fill="#3a3">s</text>
  <!-- grade 1: a vector/arrow -->
  <line x1="180" y1="90" x2="240" y2="45" stroke="#c25" stroke-width="2"/>
  <polygon points="240,45 228,48 234,57" fill="#c25"/>
  <text x="210" y="105" text-anchor="middle" font-size="13">grade 1 — vector</text>
  <text x="252" y="42" font-size="12" fill="#c25">a·e₁+b·e₂</text>
  <!-- grade 2: an oriented area -->
  <polygon points="360,85 420,85 435,45 375,45" fill="#26a44" stroke="#26a"/>
  <path d="M 378,70 A 14 14 0 0 0 402,62" fill="none" stroke="#26a"/>
  <text x="400" y="105" text-anchor="middle" font-size="13">grade 2 — bivector</text>
  <text x="398" y="38" text-anchor="middle" font-size="12" fill="#26a">p·e₁₂</text>
</svg>

The grade projections pull out each piece. Note the geometric product of
two vectors has **only** grades 0 and 2 — never grade 1:

```lean
-- a·b lives in grade 0 (the dot), a∧b in grade 2 (the wedge)
#eval gr0 (vec 1 0 * vec 1 1)      -- ⟨s := 1.0, …⟩  = a·b
#eval gr2 (vec 1 0 * vec 1 1)      -- ⟨…, e12 := 1.0⟩ = a∧b
#eval gr1 (vec 1 0 * vec 1 1)      -- ⟨all 0⟩ — no vector part
```

## 2.2 — The outer product and `a∧a = 0`

The outer product `a∧b` is the oriented parallelogram of §1.1, now taken
as an operation in its own right. Its defining property: it is
**antisymmetric**, `a∧b = −(b∧a)`. An immediate consequence — a vector
wedged with *itself* spans no area, so it vanishes:

<svg viewBox="-0.5 -2.3 6 2.8" width="440" style="background:#f4f4f8">
  <!-- a ∧ b : a real parallelogram -->
  <polygon points="0,0 2.4,0 3.2,-1.4 0.8,-1.4" fill="#7ec97e55" stroke="#3a3"/>
  <line x1="0" y1="0" x2="2.4" y2="0" stroke="#c25" stroke-width="0.05"/>
  <line x1="0" y1="0" x2="0.8" y2="-1.4" stroke="#26a" stroke-width="0.05"/>
  <text x="1.2" y="0.28" fill="#c25" font-size="0.3">a</text>
  <text x="0.2" y="-0.8" fill="#26a" font-size="0.3">b</text>
  <text x="1.6" y="-0.75" fill="#3a3" font-size="0.3">a∧b ≠ 0</text>
  <!-- a ∧ a : degenerate, zero area -->
  <g transform="translate(4.2,0)">
    <line x1="0" y1="0" x2="1.4" y2="-1.0" stroke="#c25" stroke-width="0.06"/>
    <text x="0.5" y="-0.2" fill="#c25" font-size="0.3">a</text>
    <text x="-0.1" y="-1.4" fill="#c52" font-size="0.28">a∧a = 0</text>
  </g>
</svg>

```lean
#eval wedge (vec 1 0) (vec 0 1)   -- e₁∧e₂ = e₁₂ : ⟨…, e12 := 1.0⟩
#eval wedge (vec 0 1) (vec 1 0)   -- e₂∧e₁ = −e₁₂: ⟨…, e12 := -1.0⟩
#eval wedge (vec 2 1) (vec 2 1)   -- a∧a       : ⟨all 0⟩
```

## 2.3 — Formal: antisymmetry, exactly

Over `ℤ` we can prove the grade-2 facts hold for *every* vector, not just
the examples. `a∧a = 0` is the antisymmetry law made concrete:

```lean
structure MVi where
  s : Int := 0
  e1 : Int := 0
  e2 : Int := 0
  e12 : Int := 0
deriving Repr, DecidableEq

/-- The e₁₂ coefficient of the outer product of two vectors. -/
def wedgei (a b : MVi) : Int := a.e1 * b.e2 - a.e2 * b.e1

-- a ∧ a = 0 for every vector a.
example (a : MVi) : wedgei a a = 0 := by
  unfold wedgei; rw [Int.mul_comm a.e1 a.e2]; exact Int.sub_self _

-- the unit bivector, and its reverse.
example : wedgei { e1 := 1 } { e2 := 1 } =  1 := by decide
example : wedgei { e2 := 1 } { e1 := 1 } = -1 := by decide
```

That `a∧a = 0` is the whole engine of exterior algebra: it is why the
determinant is antisymmetric, why the cross product of parallel vectors
vanishes, and (Ch 6) why the dual of a wedge recovers the cross product.

## Exercises

1. Compute `gr0`, `gr1`, `gr2` of `(1 + 2·e₁ + 3·e₁₂)` (build it with
   `MV.mk`). Which slots are non-zero?
2. Show numerically that `wedge a b = -(wedge b a)` for `a = vec 3 1`,
   `b = vec 1 2` (compute both and compare the `e12` slots).
3. In 3D there is a third basis vector `e₃` and three bivectors
   `e₁₂, e₂₃, e₃₁`. How many grades does a 3D multivector have, and how
   many basis elements in total? (Hint: count subsets of `{e₁,e₂,e₃}`.)
