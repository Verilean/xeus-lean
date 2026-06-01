# Chapter 0 — Two Worlds: Numerics and Mathlib

Before we open the first picture-and-proof chapter, we need to clear
up a Lean-specific quirk that bites everyone the first time:

> **`#eval` cannot compute Mathlib's `Complex` or `Real` numbers.**

If you ran `#eval (Real.exp 1)` on a Mathlib `import` in this kernel,
Lean would either refuse (it's `noncomputable`) or get stuck.  That
might surprise you — `Real` looks like the obvious choice for
"compute a number" — so it pays to spend ten minutes understanding
why, and how this track works around it.

## 0.1 — Why `Real` can't be evaluated

Mathlib's `ℝ` (`Real`) is defined as an equivalence class of Cauchy
sequences of rationals.  That's a perfectly good *mathematical*
definition: there really is exactly one Cauchy sequence equivalence
class corresponding to the number $\pi$.  But there's no way to ask
"what's the 128-bit floating-point approximation of $\pi$?" from the
definition alone — Lean would need a *computational* definition of
$\pi$ for that.

So `Real.pi`, `Real.exp`, `Real.cos`, and friends are all marked
`noncomputable` in Mathlib.  They exist as terms of type `ℝ`, they
satisfy theorems, you can prove things *about* them; you just can't
ask Lean to compute a digit.  Try it and the elaborator says

```
failed to compile definition, consider marking it as 'noncomputable'
because it depends on 'Real.exp', and it does not have executable code
```

This is by design, not a bug.  `Real` is the world of *formal proof
about real-valued mathematics*; computing decimals is a different
problem.

`Complex` inherits this from `Real` — it's `structure Complex where
re : ℝ; im : ℝ`, so anything involving `Real.exp` etc. is
non-evaluable.

## 0.2 — What *can* be evaluated: `Float`

Lean ships a `Float` type that *is* computable.  It maps to the
host's IEEE 754 double-precision float, with `@[extern]` bindings to
the standard C library:

```lean
-- Lean core's Float doesn't ship a π constant; we get it from acos.
def pi : Float := Float.acos (-1.0)

#eval pi                    -- 3.141593
#eval Float.exp 1.0         -- 2.718282
#eval Float.cos 0.0         -- 1.0
#eval Float.atan2 1.0 1.0   -- π/4 ≈ 0.785398
#eval (1.0 : Float).sqrt    -- 1.0
```

These run in the browser kernel, in `lean --run`, and in
`#eval`-driven notebooks alike.  Float is what you reach for when
you want to *compute*.

## 0.3 — A computable complex number

There is no `Float`-based complex number in Lean core or Mathlib, so
we'll define our own.  Keep this snippet in mind — every subsequent
chapter in this track imports it:

```lean
structure ComplexF where
  re : Float
  im : Float
deriving Repr, DecidableEq

namespace ComplexF

@[inline] def add (a b : ComplexF) : ComplexF :=
  ⟨a.re + b.re, a.im + b.im⟩

@[inline] def sub (a b : ComplexF) : ComplexF :=
  ⟨a.re - b.re, a.im - b.im⟩

@[inline] def mul (a b : ComplexF) : ComplexF :=
  ⟨a.re * b.re - a.im * b.im, a.re * b.im + a.im * b.re⟩

@[inline] def div (a b : ComplexF) : ComplexF :=
  let d := b.re * b.re + b.im * b.im
  ⟨(a.re * b.re + a.im * b.im) / d, (a.im * b.re - a.re * b.im) / d⟩

@[inline] def neg (a : ComplexF) : ComplexF := ⟨-a.re, -a.im⟩

@[inline] def absSq (a : ComplexF) : Float := a.re * a.re + a.im * a.im
@[inline] def abs (a : ComplexF) : Float   := absSq a |>.sqrt
@[inline] def arg (a : ComplexF) : Float   := Float.atan2 a.im a.re

@[inline] def conj (a : ComplexF) : ComplexF := ⟨a.re, -a.im⟩

/-- Complex exponential: e^(x + iy) = e^x (cos y + i sin y). -/
@[inline] def exp (a : ComplexF) : ComplexF :=
  let m := a.re.exp
  ⟨m * a.im.cos, m * a.im.sin⟩

/-- Convenience constructor: 0 + 1·i. -/
def I : ComplexF := ⟨0, 1⟩

/-- Real number as ComplexF. -/
def ofReal (r : Float) : ComplexF := ⟨r, 0⟩

instance : Add ComplexF := ⟨add⟩
instance : Sub ComplexF := ⟨sub⟩
instance : Mul ComplexF := ⟨mul⟩
instance : Div ComplexF := ⟨div⟩
instance : Neg ComplexF := ⟨neg⟩
instance : OfNat ComplexF n where
  ofNat := ⟨Float.ofNat n, 0⟩

/-- Pretty: "3.14 + 0.50i". -/
def repr (a : ComplexF) : String :=
  s!"{a.re} + {a.im}i"

end ComplexF
```

That defines everything we need to compute with complex numbers in
the browser.  Quick sanity checks:

```lean
open ComplexF

#eval (1 + I) * (1 + I)       -- (0 + 2i): i² = -1 in action
#eval (I).exp                 -- e^i = cos 1 + i sin 1 ≈ (0.54, 0.84)
#eval (ofReal pi * I).exp  -- e^(iπ) = -1: floating-point noise nearby
#eval abs (1 + I)             -- √2 ≈ 1.414
#eval arg (1 + I)             -- π/4 ≈ 0.785
```

All run, all return a number.  This is the world of *numerics*.

## 0.4 — Why we still want Mathlib

So if `Float` works and `Real` doesn't compute, why bother with
Mathlib?

Because numerics tells you *what something is approximately*, but
proof tells you *what something is exactly*.  When we want to assert
"the integral of $1/(x^2+1)$ over $\mathbb{R}$ is exactly $\pi$",
that's a statement about Mathlib's `Real`, not about a Float.  No
amount of `#eval` over Float samples will *prove* the integral
equals $\pi$ — it will only show "the trapezoid rule with 4000
points gives 3.1415something."

So this track uses both:

| Goal | Language | Where in a cell |
|---|---|---|
| "Let me see this concretely" | `Float` / `ComplexF` | `#eval` cells |
| "Let me state this exactly" | `Real` / `Complex` (Mathlib) | `example`, `theorem` cells |

Numerics shows you the pattern.  Mathlib *proves* the pattern.

## 0.5 — Worked example: $e^{i\pi} = -1$

Numerically, via `ComplexF`:

```lean
open ComplexF
#eval (ofReal pi * I).exp
-- (-1.0, 1.2246467991473532e-16) — basically -1, with rounding fuzz
#eval abs ((ofReal pi * I).exp + 1)
-- ≈ 1.2e-16: the distance from e^(iπ) to -1 is one float ULP
```

Formally, via Mathlib:

```lean
import Mathlib.Analysis.SpecialFunctions.Complex.Circle
open Complex

example : Complex.exp (Complex.I * (Real.pi : ℂ)) = -1 := by
  -- Mathlib provides this as `Complex.exp_pi_mul_I`.
  exact Complex.exp_pi_mul_I
```

Two cells, two worlds.  The numerical cell *shows you*, the formal
cell *proves it*.

## 0.6 — A note on `Lemma sketch` cells in later chapters

Many later chapters end the formal section with a cell like

```lean
example : ... := by
  sorry
```

`sorry` is Lean's "trust me, this is true" placeholder; it lets the
file type-check while leaving the proof for the reader.  Cells with
`sorry` will *type-check* (the statement is well-formed) but won't
*prove* (Lean still loudly warns "declaration uses 'sorry'").

That's intentional in a tutorial: we're showing what the formal
statement looks like, not delivering a Mathlib pull-request.  If a
chapter ends with three `sorry`s, those are the "prove it yourself"
exercises.

## 0.7 — Loading the Numerics module in later chapters

From Chapter 1 on, each chapter starts with:

```lean
%load mathlib       -- only if the chapter uses Mathlib lemmas
```

then a cell that pulls in the numerical helper:

```lean
-- Inline the ComplexF definition (the kernel doesn't yet support
-- cross-cell imports the way a project would).  Copy from §0.3
-- above, or simply re-paste the block.
```

When xeus-lean grows real cross-notebook `import` support (see
todo #57), this'll collapse to one line.  For now, the inline
re-paste is the working ergonomic.

## 0.8 — Recap

- Mathlib's `Real` / `Complex` are noncomputable; `#eval` won't run
  them.
- `Float` is computable; we built `ComplexF` on top of it.
- Numerical cells use `ComplexF`; formal statements use `Complex`.
- Both worlds are present in this track; each chapter uses both.

With that out of the way, on to Chapter 1.
