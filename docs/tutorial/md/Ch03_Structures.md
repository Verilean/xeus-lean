# Chapter 3 — Structures and type classes

`inductive` is good for sum types ("a value is *one of* these").
For product types ("a value has *all* these fields") `structure`
is what you want. Type classes then let you teach Lean how your
types interact with built-in operators like `+`, `==`, `toString`.

## 3.1 `structure` — records with named fields

```lean
structure Point where
  x : Float
  y : Float
  deriving Repr

def origin : Point := { x := 0.0, y := 0.0 }

#eval origin
```
```output
{ x := 0.000000, y := 0.000000 }
```

Field access uses dot notation:

```lean
#eval origin.x
```
```output
0.000000
```

Anonymous-constructor syntax `⟨...⟩` is shorter for positional
construction:

```lean
def p : Point := ⟨3.0, 4.0⟩
#eval p
```
```output
{ x := 3.000000, y := 4.000000 }
```

The braces form is named (`{ x := 3.0, y := 4.0 }`), the angle
brackets are positional (`⟨3.0, 4.0⟩`). Pick whichever reads
better at the call site.

## 3.2 Functional updates

Lean's record-update syntax mirrors Haskell's:

```lean
def shiftedRight (p : Point) (dx : Float) : Point :=
  { p with x := p.x + dx }

#eval shiftedRight ⟨1.0, 2.0⟩ 10.0
```
```output
{ x := 11.000000, y := 2.000000 }
```

`{ p with field := value }` returns a *new* record. Lean is
purely functional — there's no in-place mutation here.

## 3.3 Methods via dot notation

Define a function in a namespace matching the type, and dot
notation finds it automatically:

```lean
namespace Point

def distance (p q : Point) : Float :=
  let dx := p.x - q.x
  let dy := p.y - q.y
  Float.sqrt (dx * dx + dy * dy)

end Point

#eval (⟨0.0, 0.0⟩ : Point).distance ⟨3.0, 4.0⟩
```
```output
5.000000
```

`p.distance q` desugars to `Point.distance p q`. This is the
"methods are functions whose first arg is the receiver" idiom
you might know from Go or Rust.

## 3.4 Type classes — making `+` work for your type

Operators in Lean are *not* hard-wired to specific types. `+` is
notation for `HAdd.hAdd` (heterogeneous add), which dispatches on
the operand types. To make `+` work on `Point`s, provide an
`Add` instance:

```lean
instance : Add Point where
  add a b := ⟨a.x + b.x, a.y + b.y⟩

#eval (⟨1.0, 2.0⟩ : Point) + ⟨10.0, 20.0⟩
```
```output
{ x := 11.000000, y := 22.000000 }
```

The same pattern works for `-`, `*`, `/`, `<`, `==`, etc. — each
operator has a class (`Sub`, `Mul`, `Div`, `LT`, `BEq`, …).

## 3.5 `ToString` — controlling how `#eval` prints

`#eval x` ultimately calls `ToString.toString x` for many types.
Provide an instance to customise:

```lean
instance : ToString Point where
  toString p := s!"({p.x}, {p.y})"

#eval (⟨3.0, 4.0⟩ : Point)
```
```output
(3.000000, 4.000000)
```

(`Repr` is similar but aimed at *debugging* output; it usually
shows the full constructor / record syntax. `ToString` is for
human-facing rendering. Many types derive both.)

## 3.6 `BEq` and `Hashable` — collection-friendliness

To use your type as a key in a `HashSet` / `HashMap` (Chapter 7),
you need `BEq` (boolean equality) and `Hashable`:

```lean
instance : BEq Point where
  beq a b := a.x == b.x && a.y == b.y

#eval (⟨1.0, 2.0⟩ : Point) == ⟨1.0, 2.0⟩
#eval (⟨1.0, 2.0⟩ : Point) == ⟨1.0, 3.0⟩
```
```output
true
false
```

Both can also be `deriving`-ed in many cases:

```lean
structure UserId where
  raw : Nat
  deriving Repr, BEq, Hashable

#eval (⟨1⟩ : UserId) == ⟨1⟩
```
```output
true
```

## 3.7 `Ord` — sorting

```lean
instance : Ord Point where
  compare a b :=
    match compare a.x b.x with
    | .eq => compare a.y b.y
    | order => order

#eval compare (⟨1.0, 2.0⟩ : Point) ⟨1.0, 3.0⟩
```
```output
Ordering.lt
```

`Ordering.lt`, `.eq`, `.gt` are the three possible answers. Once
`Ord` is in scope you can use `<`, `≤`, `min`, `max`, and pass
the type to sorting functions.

## 3.8 Parameterised structures

Like Haskell records, structures can be polymorphic:

```lean
structure Pair (α β : Type) where
  fst : α
  snd : β
  deriving Repr

#eval (⟨"hello", 42⟩ : Pair String Nat)
```
```output
{ fst := "hello", snd := 42 }
```

Lean's built-in `Prod α β` (used implicitly by `(a, b)` tuples)
is exactly this with prettier syntax.

## 3.9 Inheritance — `extends`

`structure A extends B` gives you all of B's fields plus your own
(single inheritance, multiple `extends` allowed):

```lean
structure Animal where
  name : String
  age  : Nat
  deriving Repr

structure Dog extends Animal where
  breed : String
  deriving Repr

def rex : Dog := { name := "Rex", age := 5, breed := "Labrador" }

#eval rex
#eval rex.name
#eval rex.breed
```
```output
{ toAnimal := { name := "Rex", age := 5 }, breed := "Labrador" }
"Rex"
"Labrador"
```

The parent record sits inside `.toAnimal`; field access on it
(`rex.name`) is auto-forwarded.

## 3.10 Recap

You can now:

- define records with `structure ... where ...`
- update with `{ r with field := value }`
- attach "methods" via namespaced functions + dot notation
- teach Lean about `+` / `==` / `<` / `toString` for your types via instances
- `deriving Repr, BEq, Hashable, Ord` for the boilerplate cases
- extend records via `extends`

In the next chapter (coming soon) we'll switch to **data
structures**: lists, arrays, and the standard hash containers.
That's where these abstractions earn their keep — when you start
storing your records in collections and asking the compiler to
keep the invariants straight.
