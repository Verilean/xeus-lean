# Chapter 1 — Continuity

## 1.1 — The ε–δ picture

A function $f$ is *continuous at* $x_0$ when, for every horizontal
band of height $2\varepsilon$ around $f(x_0)$, there's a vertical
slab of width $2\delta$ around $x_0$ whose image lies entirely inside
the band.

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 320 220" width="320" height="220">
  <defs>
    <marker id="arr" viewBox="0 0 10 10" refX="9" refY="5"
            markerUnits="strokeWidth" markerWidth="6" markerHeight="6" orient="auto">
      <path d="M0,0 L10,5 L0,10 Z" fill="#333"/>
    </marker>
  </defs>

  <!-- axes -->
  <line x1="20" y1="200" x2="310" y2="200" stroke="#333" marker-end="url(#arr)"/>
  <line x1="40" y1="210" x2="40" y2="10"  stroke="#333" marker-end="url(#arr)"/>

  <!-- ε band (horizontal stripes around f(x0)) -->
  <rect x="40" y="90" width="270" height="40" fill="#cce5ff" opacity="0.7"/>
  <text x="315" y="115" font-size="11" fill="#0066cc">ε-band</text>

  <!-- δ slab (vertical) -->
  <rect x="155" y="10" width="40" height="190" fill="#ffe0cc" opacity="0.7"/>
  <text x="160" y="20" font-size="11" fill="#cc6600">δ-slab</text>

  <!-- curve f(x) -->
  <path d="M40 200 Q 175 -20 310 50" stroke="#222" fill="none" stroke-width="2"/>

  <!-- centre point -->
  <circle cx="175" cy="110" r="3.5" fill="#cc0000"/>
  <text x="180" y="105" font-size="11">(x₀, f(x₀))</text>

  <text x="170" y="218" font-size="11">x₀</text>
  <text x="22"  y="115" font-size="11">f(x₀)</text>
</svg>
```

The blue band is the *output tolerance* ε.  The orange slab is the
*input tolerance* δ we have to find.  Continuity at $x_0$ is the
guarantee that no matter how thin you make the blue band, an orange
slab exists.

## 1.2 — A concrete check: $f(x) = x^2 + 1$ near $x_0 = 1$

At $x_0 = 1$, $f(x_0) = 2$.  We expand:

$$
f(1 + \delta) - f(1) = (1+\delta)^2 + 1 - 2 = 2\delta + \delta^2.
$$

Plugging in tiny δ:

```lean
def f (x : Float) : Float := x*x + 1.0
def diff (delta : Float) : Float := (f (1.0 + delta) - f 1.0).abs

#eval diff 0.01    -- ≈ 0.020100
#eval diff 0.001   -- ≈ 0.002001
#eval diff 0.0001  -- ≈ 0.000200
```

Expected:

```output
0.020100
0.002001
0.000200
```

So a quick rule of thumb: $|f(1+\delta) - f(1)| \le 3|\delta|$ for
$|\delta| \le 1$, hence the constructive choice

$$
\delta = \varepsilon / 3
$$

works for any ε at this point.

```lean
def deltaFor (eps : Float) : Float := eps / 3.0
#eval deltaFor 0.01    -- 0.003333
#eval deltaFor 0.0001  -- 0.000033
```

Expected:

```output
0.003333
0.000033
```

## 1.3 — Intermediate value theorem, numerically

A continuous function on $[a, b]$ that crosses zero must hit zero.
That's the *intermediate value theorem* (IVT), and it gives you the
bisection root-finder for free.  Take $g(x) = x^3 - x - 1$ on $[1, 2]$:
$g(1) = -1 < 0 < 5 = g(2)$, so IVT promises a root.

```lean
partial def bisect (g : Float → Float) (lo hi : Float) (n : Nat) : Float :=
  if n = 0 then (lo + hi) / 2.0
  else
    let m := (lo + hi) / 2.0
    if g lo * g m < 0.0 then bisect g lo m (n - 1)
    else bisect g m hi (n - 1)

#eval bisect (fun x => x*x*x - x - 1.0) 1.0 2.0 40
```

Expected (the *plastic constant*, root of $x^3 = x + 1$):

```output
1.324718
```

40 halvings of an interval of length 1 leaves a window of width
$2^{-40} \approx 10^{-12}$, so the 6 digits printed are already
trustworthy.

## 1.4 — The formal statement

`Mathlib.Topology.ContinuousFunction` gives continuity on `ℝ`:

```lean
import Mathlib.Topology.ContinuousFunction.Basic
import Mathlib.Analysis.SpecialFunctions.Polynomials

open scoped Topology

-- Polynomials are continuous on ℝ.
example : Continuous (fun x : ℝ => x^2 + 1) := by
  exact (continuous_pow 2).add continuous_const

-- The ε–δ definition unfolds to a `Metric.continuousAt_iff`:
example (f : ℝ → ℝ) (x₀ : ℝ) :
    ContinuousAt f x₀ ↔
    ∀ ε > 0, ∃ δ > 0, ∀ x, |x - x₀| < δ → |f x - f x₀| < ε :=
  Metric.continuousAt_iff
```

And the IVT proper:

```lean
-- The intermediate value theorem on a continuous real function.
example {f : ℝ → ℝ} (hf : Continuous f) {a b : ℝ} (hab : a ≤ b)
    {y : ℝ} (h₁ : f a ≤ y) (h₂ : y ≤ f b) :
    ∃ x ∈ Set.Icc a b, f x = y :=
  intermediate_value_Icc hab hf.continuousOn ⟨h₁, h₂⟩
```

So the bisection cell from §1.3 is the *algorithmic shadow* of
`intermediate_value_Icc`: same hypothesis, same conclusion, one
returns a `Float` to six digits and the other returns a witness in
`Set.Icc a b`.

Next: [Chapter 2 — Derivatives](Ch02_Derivatives.md).
