# Chapter 1 — Values and Functions

Lean 4 is a strongly-typed functional language. Most of what you
already know from Haskell, OCaml, or Rust (the functional bits)
transfers; the only really new ideas are *dependent types* and
*tactics*, which we defer to later.

This chapter is just the surface: how to define values, how to
define functions, and how the REPL talks to you.

## 1.1 `def` — naming a value

```lean
def answer : Nat := 42
```

`def NAME : TYPE := EXPR` introduces a name. The type annotation
is optional — Lean will infer it — but in tutorials it pays to be
explicit.

`#eval` runs an expression and prints the result. `#check` prints
the type without running anything.

```lean
#eval answer
```
```output
42
```

```lean
#check answer
```
```output
answer : Nat
```

`#eval` is your everyday "what does this compute to?" tool, like
GHCi's `print` or the Python REPL's bare expression. `#check` is
the type-level version.

## 1.2 Numeric types

Lean's number literals are polymorphic. By default they elaborate
as `Nat` (unsigned, arbitrary precision):

```lean
#check 42
```
```output
42 : Nat
```

To get a different numeric type, ascribe one:

```lean
#check (42 : Int)
```
```output
42 : Int
```

```lean
#check (42 : Float)
```
```output
42 : Float
```

Lean also has fixed-width integers (`UInt8`, `UInt16`, `UInt32`,
`UInt64`, `Int8`…`Int64`) and a `BitVec n` type for arbitrary
bit-widths.

```lean
#check (0xff : UInt8)
```
```output
0xff : UInt8
```

## 1.3 `def` with parameters — functions

A function is just a `def` with parameters before the `:`.

```lean
def addOne (n : Nat) : Nat := n + 1

#eval addOne 41
```
```output
42
```

Multi-argument functions are written by listing more parameters.
There's no syntactic difference between curried and uncurried
forms — Lean curries by default:

```lean
def add (a b : Nat) : Nat := a + b

#eval add 2 3
```
```output
5
```

Application is just juxtaposition, no parentheses required:
`add 2 3`, not `add(2, 3)`.

## 1.4 `fun` — anonymous functions

`fun x => body` is the lambda form. The `=>` is read as "maps to".

```lean
#eval (fun n => n * 2) 21
```
```output
42
```

Lean accepts a slightly nicer destructuring shorthand for `fun`:

```lean
def applyTwice (f : Nat → Nat) (x : Nat) : Nat := f (f x)

#eval applyTwice (fun n => n + 10) 5
```
```output
25
```

## 1.5 The function arrow `→`

Function types use `→` (`\to`) rather than Haskell's `->`. Both
characters are accepted; the language ships with Unicode shortcuts
in every Lean editor.

```lean
def square : Nat → Nat := fun n => n * n

#eval square 9
```
```output
81
```

You can equivalently write this in named-argument style; the two
are interchangeable.

```lean
def square' (n : Nat) : Nat := n * n

#eval square' 9
```
```output
81
```

## 1.6 Currying and partial application

Functions are curried, so applying fewer arguments yields a function:

```lean
def add3 (a b c : Nat) : Nat := a + b + c

def add3to10 := add3 10
#check add3to10
```
```output
add3to10 : Nat → Nat → Nat
```

```lean
#eval add3to10 20 12
```
```output
42
```

## 1.7 The pipeline operator `|>`

Lean has a left-to-right pipeline (Elixir / F# style):

```lean
def shoutTwice (s : String) : String :=
  s |> (· ++ "!") |> (· ++ "!")

#eval shoutTwice "hi"
```
```output
"hi!!"
```

The `·` is an *anonymous-argument placeholder*: `(· ++ "!")` desugars
to `fun s => s ++ "!"`. Combine `|>` with `·` and you get the
"method-chaining" feel familiar from Rust or Kotlin without giving
up first-class functions.

```lean
#eval [1, 2, 3, 4] |>.map (· * 2) |>.filter (· > 4) |>.sum
```
```output
14
```

`xs.map f` is sugar for `List.map f xs` (Lean's "dot notation"
auto-resolves the namespace from the receiver's type). Combined
with `|>`, you can build expressive pipelines without nesting.

## 1.8 `let` and `do` — local bindings

A `let` binds a name in a sub-expression:

```lean
def hypotenuse (a b : Float) : Float :=
  let aSq := a * a
  let bSq := b * b
  Float.sqrt (aSq + bSq)

#eval hypotenuse 3.0 4.0
```
```output
5.000000
```

Inside `do` blocks (which we'll meet in detail in the I/O chapter)
the same `let` works but `:=` becomes either `:=` (pure) or `←`
(monadic):

```lean
#eval do
  let s := "lean"
  IO.println s
  IO.println (s ++ " 4")
```
```output
lean
lean 4
```

## 1.9 `#check` for type detective work

When something doesn't typecheck or you're unsure what's going on,
`#check` is your friend. It tells you the type *without* running:

```lean
#check List.map
```
```output
@List.map : {α β : Type u_1} → (α → β) → List α → List β
```

The `{α β : Type u_1}` are *implicit* type parameters — Lean
infers them from the actual arguments — and the rest is the type
signature you'd expect.

## 1.10 Recap

You can now:

- name a value (`def x := …`) and ask for its type (`#check x`)
- write a function (`def f (n : Nat) : Nat := …` or `fun n => …`)
- pipe through `|>` with `·` for anonymous-argument lambdas
- bind locals with `let`
- use `#eval` to run things and `#check` to inspect types

Next, [Chapter 2](Ch02_Match.md): how to take an expression *apart*
with pattern matching, and how to define your own data types.
