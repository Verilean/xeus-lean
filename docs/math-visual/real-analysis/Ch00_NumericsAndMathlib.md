# Chapter 0 — Two Worlds: `Float` and `Real`

Before the first picture-and-proof chapter, the same gotcha that
opens the complex-analysis track:

> **`#eval` cannot compute Mathlib's `Real`.**

If you wrote `#eval Real.exp 1` after `import Mathlib`, Lean would
refuse — `Real.exp` is `noncomputable`.  Same story for `Real.pi`,
`Real.sin`, `Real.cos`, `Real.log`.  This is by design, not a bug,
and once you see why the rest of this track makes sense.

## 0.1 — Why `Real` can't be evaluated

Mathlib's `ℝ` (`Real`) is built as an equivalence class of Cauchy
sequences of rationals.  That's a *mathematical* definition: there
is exactly one Cauchy-equivalence class that *is* the number $\pi$,
and you can prove properties of it.  But there is no algorithm in
the definition to ask "give me the IEEE 754 approximation."  Lean
would need a *computational* definition of $\pi$ to do that — which
isn't provided.

So Mathlib marks `Real.pi`, `Real.exp`, `Real.cos`, `Real.log` as
`noncomputable`.  Try `#eval Real.exp 1` and you get:

```
failed to compile definition, consider marking it as 'noncomputable'
because it depends on 'Real.exp', and it does not have executable code
```

This is the world of *formal proof about real-valued mathematics*:
you can prove `Real.exp 1 > 2`, you can prove derivatives, you can
prove FTC — you just can't print a digit.

## 0.2 — What *can* be evaluated: `Float`

Lean ships a primitive `Float` type that is computable.  It maps to
the host's IEEE 754 double-precision float and uses `@[extern]`
C bindings:

```lean
-- Lean core's Float doesn't ship a π constant; we get it from acos.
def pi : Float := Float.acos (-1.0)

#eval pi                  -- 3.141593
#eval Float.exp 1.0       -- 2.718282
#eval Float.sin (pi/6)    -- 0.500000
#eval Float.log 2.0       -- 0.693147
#eval (2.0 : Float).sqrt  -- 1.414214
```

These run in `#eval`, in the browser kernel, in `lean --run`.  Float
is what you reach for to *compute*.

## 0.3 — The trade-off, stated once

| Need | Use |
|------|-----|
| "Show me the number" | `Float` |
| "Prove a theorem" | `Real` (from `Mathlib`) |
| Plot a function | `Float`, then plot the samples |
| Bound an error | `Real` + `abs_le`, `Filter.Tendsto`, … |

A typical chapter has both kinds of cells: `#eval` cells use `Float`
to *see* what's going on, and the formal block uses `Real` to *state*
what's true.

## 0.4 — Setup snippet (used by every later chapter)

```lean
-- Float utilities the real-analysis chapters lean on.
namespace RealF

@[inline] def linspace (a b : Float) (n : Nat) : Array Float :=
  if n ≤ 1 then #[a]
  else
    let h := (b - a) / (Float.ofNat (n - 1))
    (List.range n).toArray.map (fun i => a + Float.ofNat i * h)

@[inline] def maxAbs (xs : Array Float) : Float :=
  xs.foldl (fun acc x => max acc x.abs) 0.0

@[inline] def avg (xs : Array Float) : Float :=
  if xs.isEmpty then 0.0
  else xs.foldl (· + ·) 0.0 / Float.ofNat xs.size

end RealF
```

A quick smoke-test cell so you can confirm the kernel sees it:

```lean
#eval RealF.linspace 0.0 1.0 5   -- #[0.0, 0.25, 0.5, 0.75, 1.0]
#eval RealF.maxAbs #[1.0, -2.5, 0.3]   -- 2.5
```

Expected output:

```output
#[0.000000, 0.250000, 0.500000, 0.750000, 1.000000]
2.500000
```

## 0.5 — Where `Real` shines

When you've sampled a function on 1 000 grid points and you want to
*state* that it's continuous, `Real` is the right type.  The
`Mathlib.Topology.Continuous` API gives you `Continuous`, `IsOpen`,
limits via `Filter.Tendsto`.  We'll use them, alongside the `Float`
plots, in every chapter that follows.

```lean
import Mathlib.Topology.ContinuousFunction.Basic

open scoped Topology

example : Continuous (fun x : ℝ => x^2 + 1) := by
  exact continuous_pow 2 |>.add continuous_const
```

That's the rhythm.  Numerics on the left, formal statement on the
right, picture in between.

Next: [Chapter 1 — Continuity](Ch01_Continuity.md).
