# Chapter 8 — Conformal Geometric Algebra

> *"Add two dimensions to space, and something wonderful happens: points,
> lines, planes, circles, and spheres all become single elements — and
> every rigid motion, translation included, becomes one sandwich."*

Euclidean GA (Chapters 1–7) made *rotations* into sandwiches, but
*translations* stayed additive — an awkward exception. **Conformal
geometric algebra (CGA)** removes it. Embed 3D space into a 5D algebra
with signature `(4,1)`, and:

- a **point** becomes a null vector,
- a **sphere** or **plane** becomes an ordinary vector,
- and **every** conformal transformation — rotation, **translation**,
  dilation, inversion — becomes a versor acting by `X ↦ V X Ṽ`.

Translations become rotations (in a plane containing a null direction).
This is why CGA is the workhorse of graphics, robotics, and screw
theory. This capstone shows the two facts that make it tick, runnable.

## Setup

The conformal space adds two basis vectors, `e₊` (`e₊² = +1`) and `e₋`
(`e₋² = −1`), to `e₁, e₂, e₃`. From them, two **null** vectors: the
origin `n₀ = ½(e₋ − e₊)` and infinity `n∞ = e₋ + e₊` (both square to
zero). A 3D point `p` embeds as `P = p + ½|p|² n∞ + n₀`.

```lean
structure C5 where          -- coefficients in (e₁, e₂, e₃, e₊, e₋)
  x : Float := 0
  y : Float := 0
  z : Float := 0
  ep : Float := 0
  em : Float := 0
deriving Repr

/-- The (4,1) inner product: e₊²=+1, e₋²=−1. -/
def cdot (P Q : C5) : Float := P.x*Q.x + P.y*Q.y + P.z*Q.z + P.ep*Q.ep - P.em*Q.em

/-- Embed a 3D point as a null conformal vector  p + ½|p|² n∞ + n₀. -/
def point (x y z : Float) : C5 :=
  let r2 := x*x + y*y + z*z
  { x := x, y := y, z := z, ep := r2/2 - 0.5, em := r2/2 + 0.5 }
```

## 8.1 — Points are null vectors

The whole model rests on one identity: an embedded point squares to
zero. `p` lives on the *null cone* of the 5D space:

```lean
#eval cdot (point 0 0 0) (point 0 0 0)   -- P·P = 0
#eval cdot (point 1 2 3) (point 1 2 3)   -- P·P = 0
```

That single constraint (`P² = 0`) is what pins a 3-parameter point inside
the 5D space, and it is what makes the next fact work.

## 8.2 — The inner product *is* Euclidean distance

The conformal inner product of two points is (minus one half of) their
squared Euclidean distance — geometry, read straight off an algebraic
dot product:

$$ P \cdot Q = -\tfrac{1}{2}\,\lVert p - q \rVert^2 $$

```lean
#eval cdot (point 1 0 0) (point 4 0 0)   -- p,q on a line, |p−q|=3 → −½·9  = −4.5
#eval cdot (point 0 0 0) (point 3 4 0)   -- |p−q| = 5             → −½·25 = −12.5
```

So "are these points equal / how far apart / do they lie on this
sphere" all become inner products — no square roots, no coordinates.

## 8.3 — Everything is a versor

The payoff (stated; building the 5D product in full is beyond this
capstone): every conformal map is a sandwich `X ↦ V X Ṽ`, and it acts on
points, planes, and spheres *identically*.

| transformation | versor `V` |
|---|---|
| rotation | a rotor (Ch 3/7), unchanged |
| **translation by `t`** | `T = 1 − ½ t n∞` — a rotor in a null plane |
| dilation (scaling) | `e^{½α n₀∧n∞}` |
| inversion in a sphere | reflection in that sphere's vector |

The middle row is the headline: a **translation is a rotation** in a
plane involving `n∞`. Compose a rotation and a translation by
multiplying their versors, and you get a single **motor** — a screw
motion — the exact object robotics wants for rigid-body kinematics.

## 8.4 — Where the series has arrived

You started (Ch 1) with the claim that two vectors can be multiplied.
From that one product:

- Ch 2–3: the wedge, grades, and the **rotor** — rotation as an element
  of the algebra, `v ↦ R v R̃`.
- Ch 4: rotors are **two reflections**; that is the half-angle.
- Ch 5: the even subalgebras **are** ℂ and the quaternions.
- Ch 6: the **cross product** is the dual of the wedge — a 3D accident.
- Ch 7: 3D rotation is **quaternion** rotation, plane-first.
- Ch 8: two extra dimensions turn **every** rigid motion into one
  sandwich.

The through-line: geometry that is usually a pile of special cases —
complex numbers, quaternions, cross products, rotation matrices,
translation vectors — is one product on vectors, seen from different
dimensions. That is the *Visual Complex Analysis* the subject never had.

## Exercises

1. Verify the distance formula for `point 1 1 1` and `point 2 3 5`
   (compute `‖p−q‖²` by hand, then `cdot`).
2. `n∞ · P = −1` for every embedded point `P` (build `nInf : C5 :=
   { ep := 1, em := 1 }` and check on a few points). This normalisation
   is why the embedding is well-defined.
3. Two points are the *same* iff their conformal distance is 0. Using
   §8.2, explain why `cdot P Q = 0` means `p = q` — and why that makes
   `P² = 0` (§8.1) the statement "a point is at distance 0 from itself".
