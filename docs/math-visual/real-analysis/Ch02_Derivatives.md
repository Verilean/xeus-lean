# Chapter 2 — Derivatives

## 2.1 — The tangent as a limit

The derivative of $f$ at $x_0$ is the slope of the *tangent line*: the
limit of the slopes of secant lines as the second point slides into
$x_0$.  Same picture you've seen before, but worth one more look:

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 320 220" width="320" height="220">
  <defs>
    <marker id="arr2" viewBox="0 0 10 10" refX="9" refY="5"
            markerUnits="strokeWidth" markerWidth="6" markerHeight="6" orient="auto">
      <path d="M0,0 L10,5 L0,10 Z" fill="#333"/>
    </marker>
  </defs>

  <line x1="20" y1="200" x2="310" y2="200" stroke="#333" marker-end="url(#arr2)"/>
  <line x1="40" y1="210" x2="40" y2="10"  stroke="#333" marker-end="url(#arr2)"/>

  <!-- f(x) = x³/40 + 60, scaled to fit -->
  <path d="M40 200 Q 100 180 175 110 T 300 30" stroke="#222" fill="none" stroke-width="2"/>

  <!-- tangent at x₀ -->
  <line x1="60" y1="180" x2="290" y2="40" stroke="#cc0000" stroke-width="1.6"/>
  <text x="240" y="60" font-size="11" fill="#cc0000">tangent</text>

  <!-- secant for visible h -->
  <line x1="175" y1="110" x2="260" y2="60" stroke="#0066cc" stroke-width="1.3" stroke-dasharray="4 3"/>
  <text x="220" y="100" font-size="11" fill="#0066cc">secant</text>

  <!-- points -->
  <circle cx="175" cy="110" r="3.5" fill="#cc0000"/>
  <circle cx="260" cy="60"  r="3.5" fill="#0066cc"/>
  <text x="172" y="218" font-size="11">x₀</text>
  <text x="252" y="218" font-size="11">x₀+h</text>
</svg>
```

Numerically, this is the *forward difference*:

$$
f'(x_0) \approx \frac{f(x_0 + h) - f(x_0)}{h}.
$$

It converges to $f'(x_0)$ at first order in $h$.  The symmetric
*central difference* converges at second order — same idea, much
faster.

## 2.2 — Forward vs central differences on $f(x) = x^3$

The exact derivative at $x_0 = 2$ is $f'(2) = 3 \cdot 2^2 = 12$.

```lean
def f (x : Float) : Float := x*x*x
def fd (h : Float) : Float := (f (2.0 + h) - f 2.0) / h
def cd (h : Float) : Float := (f (2.0 + h) - f (2.0 - h)) / (2.0 * h)

#eval fd 0.1      -- forward
#eval fd 0.01
#eval fd 0.001
#eval cd 0.1      -- central
#eval cd 0.01
#eval cd 0.001
```

Expected:

```output
12.610000
12.060100
12.006001
12.010000
12.000100
12.000001
```

Notice the column of error sizes: forward shrinks by ~10× per step
($O(h)$), central by ~100× per step ($O(h^2)$).  When you're plotting
derivatives in a notebook, the central form is essentially free and
buys you two extra digits.

## 2.3 — Newton's method = derivative + secant geometry

Newton's update at the iterate $x$ is

$$
x \leftarrow x - \frac{g(x)}{g'(x)}.
$$

Geometrically, draw the tangent at $(x, g(x))$ and let it intersect
the axis; that intersection is the next iterate.  Quadratic
convergence, once you're close enough to a simple root.

Computing $\sqrt 2$ as the positive root of $g(x) = x^2 - 2$:

```lean
def newton (g g' : Float → Float) (x : Float) (n : Nat) : Float :=
  match n with
  | 0     => x
  | k + 1 => newton g g' (x - g x / g' x) k

#eval newton (fun x => x*x - 2.0) (fun x => 2.0 * x) 1.5 5
#eval Float.sqrt 2.0
```

Expected (both agree to all printed digits):

```output
1.414214
1.414214
```

5 iterations starting from 1.5 hits the IEEE 754 fixed-point.  That's
quadratic convergence — error squared each step.

## 2.4 — Mean Value Theorem (MVT), seen geometrically

For a continuous-on-$[a,b]$, differentiable-on-$(a,b)$ function $f$,
some interior point $c$ satisfies

$$
f'(c) = \frac{f(b) - f(a)}{b - a}.
$$

The tangent at $c$ is parallel to the secant from $(a, f(a))$ to
$(b, f(b))$.

For $f(x) = x^2$ on $[0, 1]$:

- Secant slope: $(1 - 0)/(1 - 0) = 1$.
- $f'(c) = 2c$.  Set $2c = 1$ ⇒ $c = 1/2$.

```lean
def mvtC : Float := 0.5
#eval 2.0 * mvtC      -- 1.000000  — equals the secant slope
```

Expected:

```output
1.000000
```

## 2.5 — The formal statement

`Mathlib.Analysis.Calculus.MeanValue` and `Mathlib.Analysis.Calculus.Deriv.Polynomial`
give you the Lean side:

```lean
import Mathlib.Analysis.Calculus.Deriv.Polynomial
import Mathlib.Analysis.Calculus.Deriv.MeanValue

open scoped Topology

-- Power-rule derivative.  HasDerivAt expresses the limit-of-secants
-- statement: f x = f x₀ + f'(x₀)(x - x₀) + o(|x - x₀|).
example (x : ℝ) : HasDerivAt (fun y : ℝ => y^3) (3 * x^2) x := by
  simpa using (hasDerivAt_pow 3 x)

-- Newton step is well-typed at a point where the derivative is nonzero.
example {g : ℝ → ℝ} {x₀ d : ℝ} (h : HasDerivAt g d x₀) (hd : d ≠ 0) :
    ∃ y : ℝ, y = x₀ - g x₀ / d := ⟨x₀ - g x₀ / d, rfl⟩

-- Mean value theorem.  Same hypotheses as the textbook.
example {f : ℝ → ℝ} {a b : ℝ} (hab : a < b)
    (hcont : ContinuousOn f (Set.Icc a b))
    (hderiv : ∀ x ∈ Set.Ioo a b, DifferentiableAt ℝ f x) :
    ∃ c ∈ Set.Ioo a b,
      deriv f c = (f b - f a) / (b - a) := by
  exact exists_deriv_eq_slope f hab hcont
    (fun x hx => (hderiv x hx).differentiableWithinAt)
```

The numeric `mvtC = 0.5` from §2.4 is one concrete value of the
existential `∃ c ∈ Set.Ioo 0 1` that MVT produces.

Next: [Chapter 3 — Integrals](Ch03_Integrals.md).
