# Chapter 6 — Duality and the Cross Product

> *"The cross product only works in 3D, and nobody tells you why. The
> reason is duality: `a × b` is the wedge `a ∧ b` in disguise."*

The cross product is a 3D-only oddity — it takes two vectors and returns
a third vector, perpendicular to both, with a right-hand rule bolted on.
Geometric algebra explains it. The honest object is the bivector
`a ∧ b` (an oriented *plane*); the cross product is its **dual** — the
one vector left perpendicular to that plane. Duality is the operation
that turns a `k`-blade into the `(n−k)`-blade orthogonal to it, and in
3D it turns the plane `a ∧ b` into the axis `a × b`.

## Setup

We work in 3D. A vector and a bivector each need three components; we
store both as a `V3` (for a bivector, the components are the `e₂₃`,
`e₃₁`, `e₁₂` planes).

```lean
structure V3 where
  x : Float := 0
  y : Float := 0
  z : Float := 0
deriving Repr, BEq

/-- a ∧ b, as a bivector (its e₂₃, e₃₁, e₁₂ coefficients). -/
def wedge3 (a b : V3) : V3 :=
  { x := a.y*b.z - a.z*b.y, y := a.z*b.x - a.x*b.z, z := a.x*b.y - a.y*b.x }
/-- The dual ⋆ : e₂₃ ↦ e₁, e₃₁ ↦ e₂, e₁₂ ↦ e₃ — same components, new meaning. -/
def dual (B : V3) : V3 := B
/-- The cross product is the dual of the wedge. -/
def cross (a b : V3) : V3 := dual (wedge3 a b)

def e1 : V3 := { x := 1 }
def e2 : V3 := { y := 1 }
def e3 : V3 := { z := 1 }
```

## 6.1 — The pseudoscalar and duality

The highest-grade element `I = e₁₂₃` is the **pseudoscalar** — the
oriented unit volume. Multiplying by it (the dual `⋆M = M I⁻¹`) swaps a
grade-`k` blade for the grade-`(3−k)` blade orthogonal to it:

| blade | grade | its dual |
|---|---|---|
| `1` (scalar) | 0 | `e₁₂₃` (pseudoscalar) |
| `e₁` (vector) | 1 | `e₂₃` (a plane) |
| `e₂₃` (bivector) | 2 | `e₁` (a vector) |
| `e₁₂₃` | 3 | `1` |

The middle two rows are the interesting ones: a **plane** and its
**normal vector** are duals. That is the whole content of the cross
product.

## 6.2 — `a × b = ⋆(a ∧ b)`

`a ∧ b` is the oriented plane the two vectors span; `⋆` returns the
vector perpendicular to it, of the same magnitude (the area). That
vector is exactly `a × b`:

<svg viewBox="-1.6 -1.8 4 3.4" width="380" style="background:#f4f4f8">
  <!-- the plane a∧b as a parallelogram -->
  <polygon points="0,0 1.6,0.4 2.4,-0.5 0.8,-0.9" fill="#7ec97e44" stroke="#3a3"/>
  <line x1="0" y1="0" x2="1.6" y2="0.4" stroke="#c25" stroke-width="0.05"/>
  <line x1="0" y1="0" x2="0.8" y2="-0.9" stroke="#26a" stroke-width="0.05"/>
  <text x="1.3" y="0.6" fill="#c25" font-size="0.28">a</text>
  <text x="0.2" y="-0.6" fill="#26a" font-size="0.28">b</text>
  <text x="1.2" y="-0.25" fill="#3a3" font-size="0.26">a∧b (plane)</text>
  <!-- the normal a×b -->
  <line x1="0.9" y1="-0.3" x2="0.9" y2="-1.6" stroke="#c52" stroke-width="0.06"/>
  <polygon points="0.9,-1.6 0.78,-1.4 1.02,-1.4" fill="#c52"/>
  <text x="1.0" y="-1.4" fill="#c52" font-size="0.28">a×b = ⋆(a∧b)</text>
</svg>

```lean
#eval cross e1 e2     -- e₁×e₂ = e₃  → ⟨x:=0, y:=0, z:=1⟩
#eval cross e2 e3     -- e₂×e₃ = e₁  → ⟨x:=1, …⟩
#eval cross e1 e1     -- a×a = 0     → ⟨0,0,0⟩
```

## 6.3 — Why only 3D

The dual of a bivector is a vector **only when `n − 2 = 1`**, i.e. only
in 3D. In 2D the dual of `a ∧ b` is a *scalar* (Ch 1's signed area); in
4D it is *another bivector*. So the cross product — "wedge, then dual to
a vector" — is a coincidence of three dimensions. The wedge `a ∧ b`
works in every dimension; only its packaging as a vector is special.
Prefer the wedge, and the cross product becomes a 3D convenience rather
than a load-bearing definition.

## 6.4 — Formal

Over `ℤ` the wedge (hence the cross product) obeys the expected facts
exactly:

```lean
structure V3i where
  x : Int := 0
  y : Int := 0
  z : Int := 0
deriving Repr, DecidableEq

def wedge3i (a b : V3i) : V3i :=
  { x := a.y*b.z - a.z*b.y, y := a.z*b.x - a.x*b.z, z := a.x*b.y - a.y*b.x }

example : wedge3i { x := 1 } { y := 1 } = { z := 1 } := by decide          -- e₁∧e₂ = e₁₂
example : wedge3i { x := 2, y := 3, z := 1 } { x := 2, y := 3, z := 1 } = {} := by decide  -- a∧a = 0
```

## Exercises

1. Compute `cross e2 e1` and confirm it is `−e₃`. Anti­symmetry of the
   wedge is anti­symmetry of the cross product.
2. Check the right-hand rule numerically for `cross e3 e1` — is it `e₂`?
3. In 2D, `a ∧ b` is a scalar (its `e₁₂` coefficient). Argue that "the
   2D cross product" people write is really `⋆(a∧b)` landing in grade 0,
   not grade 1 — which is why it is a *number*, not a vector.
