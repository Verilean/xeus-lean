# Chapter 2 — Pattern matching and inductive types

Pattern matching is how you take a value apart. Inductive types
are how you define your own values to take apart. Together they
cover roughly 80% of day-to-day Lean.

## 2.1 `match` on `Nat`

`Nat` is defined as either `0` or `.succ n` (where `n : Nat`).
Pattern matching just walks that definition:

```lean
def isZero (n : Nat) : Bool :=
  match n with
  | 0     => true
  | _ + 1 => false

#eval isZero 0
#eval isZero 5
```
```output
true
false
```

`_ + 1` is a *pattern*: it matches any `Nat` that's a successor,
binding nothing. To bind, name the predecessor:

```lean
def pred (n : Nat) : Nat :=
  match n with
  | 0     => 0
  | k + 1 => k

#eval pred 0
#eval pred 7
```
```output
0
6
```

## 2.2 `Option` — values that might not be there

`Option α` has two constructors: `none` and `some a`. Use it
wherever in another language you'd reach for nullable / `Maybe`.

```lean
def lookup (k : String) : Option Nat :=
  if k == "answer" then some 42 else none

#eval lookup "answer"
#eval lookup "zero"
```
```output
some 42
none
```

Pattern-match to consume one:

```lean
def describe (x : Option Nat) : String :=
  match x with
  | none   => "missing"
  | some n => s!"got {n}"

#eval describe (lookup "answer")
#eval describe (lookup "zero")
```
```output
"got 42"
"missing"
```

`s!"..."` is *string interpolation*: `{e}` is replaced by
`toString e` at runtime.

## 2.3 `if let` shorthand

When you only care about one branch, `if let` is shorter than a
full `match`:

```lean
def shout (x : Option String) : String :=
  if let some s := x then s.toUpper else ""

#eval shout (some "lean")
#eval shout none
```
```output
"LEAN"
""
```

## 2.4 Tuples and `Prod`

A 2-tuple is `(a, b)` and has type `α × β`. Pattern-match it
like a constructor:

```lean
def addPair (p : Nat × Nat) : Nat :=
  match p with
  | (a, b) => a + b

#eval addPair (3, 4)
```
```output
7
```

For longer tuples it's often cleaner to destructure in the
parameter list:

```lean
def midpoint : (Float × Float) → (Float × Float) → (Float × Float)
  | (x₁, y₁), (x₂, y₂) => ((x₁ + x₂) / 2, (y₁ + y₂) / 2)

#eval midpoint (0.0, 0.0) (4.0, 6.0)
```
```output
(2.000000, 3.000000)
```

The bar-style definition is sugar for one big `match`.

## 2.5 Your own inductive types

`inductive` introduces a new type by listing its constructors.

```lean
inductive Colour
  | red
  | green
  | blue
  | rgb (r g b : UInt8)
  deriving Repr

#check Colour.red
```
```output
Colour.red : Colour
```

`deriving Repr` asks Lean to auto-generate a printer (the
equivalent of Haskell's `deriving Show`). Without it, `#eval` of
a `Colour` value would fail to show anything useful.

Pattern-match like any built-in:

```lean
def colourName : Colour → String
  | .red   => "red"
  | .green => "green"
  | .blue  => "blue"
  | .rgb r g b => s!"#{r}{g}{b}"

#eval colourName .red
#eval colourName (.rgb 255 0 128)
```
```output
"red"
"#25500128"
```

The leading dot — `.red`, `.rgb` — is the *anonymous constructor*
syntax: Lean infers the namespace from the expected type. The
full form would be `Colour.red`.

> The decimal `255 0 128` rendering above is a small wart: `UInt8`
> `toString` gives the base-10 digits without zero-padding. Real
> code typically formats with a small helper; we'll write one in
> Chapter 6 once we have strings.

## 2.6 Recursive inductive types

`List` is the prototypical recursive type:

```lean
inductive MyList (α : Type)
  | nil
  | cons (head : α) (tail : MyList α)
  deriving Repr
```

Recursion-following functions on it are also recursive:

```lean
def length : MyList α → Nat
  | .nil => 0
  | .cons _ tail => 1 + length tail

#eval length (.cons 1 (.cons 2 (.cons 3 .nil)))
```
```output
3
```

(Lean's built-in `List α` is exactly this with nicer syntax —
`[]` for `nil`, `::` for `cons`. We'll move to it in Chapter 4.)

## 2.7 `where` for helper definitions

A local recursive helper inside a `def` reads more cleanly than
nested `let rec`:

```lean
def countDown (n : Nat) : List Nat := loop n []
where
  loop : Nat → List Nat → List Nat
    | 0,     acc => acc
    | k + 1, acc => loop k (k + 1 :: acc)

#eval countDown 5
```
```output
[5, 4, 3, 2, 1]
```

`where` is mutually-recursive-friendly: list more clauses
separated by `:=` and they all see each other.

## 2.8 Exhaustiveness

Lean's compiler statically checks that every `match` covers every
constructor. Leave a case out and you get an error — there is no
"runtime missing-match" failure unless you actively use `panic!`.

```lean
-- ✗ won't compile: missing the `.cons` case
-- def buggy : MyList Nat → Nat
--   | .nil => 0
```

This catches an enormous class of bugs that other languages can
only catch at runtime.

## 2.9 Recap

You can now:

- pattern-match on `Nat`, `Option`, tuples, and your own types
- define your own inductive types with `inductive ... | ...`
- use `if let` for one-branch matches
- use anonymous-constructor `.name` syntax
- define helpers with `where`
- rely on the compiler's exhaustiveness check

Next, [Chapter 3](Ch03_Structures.md): records, type classes, and
how to make your types interact with `+`, `==`, `toString`, etc.
