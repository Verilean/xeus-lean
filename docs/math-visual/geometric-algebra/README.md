# Geometric Algebra — Visual Track

Chapters covering **geometric (Clifford) algebra** in the spirit of
Tristan Needham's *Visual Complex Analysis*: a picture per idea, then a
numerical cell you can run, then a formal statement, then exercises.

There is, as far as we know, no "*Visual Complex Analysis* for geometric
algebra". This track is an attempt at one — building the intuition for
bivectors, rotors, and reflections from pictures rather than from
axioms.

**Why geometric algebra.** One product on vectors — the *geometric
product* `ab = a·b + a∧b` — unifies the dot product, the cross product,
complex numbers, quaternions, rotations, and reflections. The even
subalgebra of the 2D geometric algebra *is* the complex numbers, and of
the 3D one *is* the quaternions (Ch 05), so this track is a natural
sequel to the [Complex Analysis](../complex-analysis/README.md) one.

| Chapter | Topic |
|---|---|
| [Ch01 The geometric product](Ch01_GeometricProduct.md) | `ab = a·b + a∧b`; the bivector as oriented area; why `e₁e₂ = −e₂e₁` |
| [Ch02 The outer product & grades](Ch02_OuterProduct.md) | `a∧b`, `a∧a=0`, grades 0–2, grade projection |
| [Ch03 Rotors](Ch03_Rotors.md) | `v ↦ R v R̃`, `R = e^{−e₁₂θ/2}`; rotation without matrices; the half-angle |
| [Ch04 Reflections](Ch04_Reflections.md) | `v ↦ n v n`; two reflections compose to a rotation by twice the angle |
| [Ch05 ℂ and ℍ inside](Ch05_ComplexQuaternion.md) | Cl⁺(2) ≅ ℂ (proven), Cl⁺(3) ≅ ℍ; a rotor is a unit complex / quaternion |
| [Ch06 Duality & the cross product](Ch06_Duality.md) | pseudoscalar, `a×b = ⋆(a∧b)`, why it's 3D-only |
| [Ch07 Rotations in 3D](Ch07_3DRotations.md) | full 3D geometric product; quaternion rotation, plane-first |
| [Ch08 Conformal GA](Ch08_ConformalGA.md) | points as null vectors, distance = inner product, translations as versors |

## How each chapter is shaped

1. **Opening framing** — one paragraph on the idea.
2. **Picture** — an inline SVG of the geometric content.
3. **Numerical exploration** — Lean `#eval` on a small Float-backed
   multivector type, so you can *see* the numbers.
4. **Formal statement** — the defining relations proven exactly (over
   ℤ), or (in later chapters) Mathlib's `CliffordAlgebra`.
5. **Exercises.**

Read them in order; each builds on the previous.
