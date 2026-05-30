# Chapter 16 — Type-Level Programming (with comparisons to Haskell)

Lean 4 is a *dependent type theory*: types and values share the same
language, sit in the same files, and can be passed to each other.
That makes the distinction Haskell draws between "term level" and
"type level" mostly disappear — you don't need a separate `DataKinds`
extension to lift a value to a type, you just use it.

This chapter walks the Haskell type-level toolkit and shows the Lean
equivalent.  Where Haskell needs a language extension and a clever
encoding, Lean usually just does it.  Where Haskell has something
Lean doesn't (or vice versa), I'll say so explicitly.

## 16.1 Type application — passing a type as an argument

In Haskell, `f @Int x` passes `Int` as the type for `f`'s first
type variable; you need `-XTypeApplications`.

```haskell
-- Haskell
read @Int "42"           -- 42 :: Int
show @Bool True          -- "True"
```

In Lean it's just an ordinary argument with `@`:

```lean
-- Lean
#eval @id Nat 5                  -- 5
#eval @Function.const Nat String "ignored" 0
-- explicit type arg is "Nat", value arg is "ignored", index arg is 0
```

The leading `@` in Lean turns *all* implicits into explicit
positional arguments.  Haskell's `@T` only fills the first; Lean is
all-or-nothing, but you can recover Haskell's behaviour with a named
argument:

```lean
#eval id (α := Nat) 5            -- same as above, only `α` is explicit
```

**Haskell parity:** Lean's named arguments cover Haskell's
`-XTypeApplications` and then some — you can target any implicit by
name, not just the leftmost.

## 16.2 Values to types — promoting data

Haskell needs `-XDataKinds` to lift a value-level constructor up:

```haskell
-- Haskell
data Nat = Z | S Nat
-- with DataKinds, 'Z and 'S Nat become types,
-- and you index by them: data Vec (n :: Nat) a where ...
```

Lean: no extension, no quote, no promotion.  Types are just terms:

```lean
inductive Nat' : Type where
  | z : Nat'
  | s : Nat' → Nat'

-- Use a Nat' VALUE directly as a type index:
inductive Vec (α : Type) : Nat' → Type where
  | nil  : Vec α .z
  | cons : α → Vec α n → Vec α (.s n)

-- A vector of three Bool's, length tracked in the TYPE:
def threeBools : Vec Bool (.s (.s (.s .z))) :=
  .cons true (.cons false (.cons true .nil))

#check threeBools     -- Vec Bool (Nat'.s (Nat'.s (Nat'.s Nat'.z)))
```

The `Nat'.s (Nat'.s (Nat'.s Nat'.z))` is a *value of type `Nat'`* that
also happens to appear inside a type.  No promotion, no kind, no
`'-prefix`.

**Haskell parity:** Haskell's `DataKinds` + `GADTs` together give you
roughly this.  Lean folds both into the base language.

## 16.3 Types to values — singletons aren't needed

In Haskell, going the other direction (using a type-level value as
runtime data) requires *singletons*:

```haskell
-- Haskell, with singletons
data SNat (n :: Nat) where
  SZ :: SNat 'Z
  SS :: SNat n -> SNat ('S n)
-- and `fromSing :: SNat n -> Nat` to get the value back at runtime
```

Lean: every value-of-`Nat` is already a runtime value.  No singleton
duplication.

```lean
-- A value n : Nat' is itself runtime data.  Pattern-match on it:
def toString' : Nat' → String
  | .z       => "0"
  | .s n     => "S " ++ toString' n

#eval toString' (.s (.s .z))         -- "S S 0"
```

The same `Nat'.s (Nat'.s ...)` that was a type index two cells up is,
in this cell, a value being pattern-matched.  That is the dependent-
types trick: types *are* values.

**Haskell parity:** singleton libraries (`singletons`, `singletons-th`)
are the standard workaround.  Lean doesn't need them — the
distinction they paper over doesn't exist here.

## 16.4 Type families ≈ definitions returning types

Haskell type families compute a type from other types:

```haskell
-- Haskell
type family Container (n :: Nat) a where
  Container 'Z     a = ()
  Container ('S n) a = (a, Container n a)
```

In Lean: a function that *returns* a type.  You're computing in the
`Type` universe instead of `Nat`.

```lean
def Container : Nat → Type → Type
  | 0,     _ => Unit
  | n + 1, α => α × Container n α

#check (Container 3 Bool)
-- Bool × (Bool × (Bool × Unit))

example : Container 3 Bool := (true, false, true, ())
```

Read that left-to-right: the recursion happens at *definition* time;
by the time Lean type-checks the example body, `Container 3 Bool` has
already reduced to the nested tuple type.

**Haskell parity:** closed type families = pattern-matching Lean
function over `Type`.  No need for closed/open distinction.

## 16.5 Constraints ≈ instance arguments

Haskell uses `=>` to thread type-class evidence:

```haskell
sortAll :: Ord a => [a] -> [a]
```

Lean uses `[...]` for instance arguments:

```lean
def sortAll [Ord α] (xs : List α) : List α := xs.mergeSort
#eval sortAll [3, 1, 4, 1, 5, 9, 2, 6]
```

Mostly the same idea.  Differences worth knowing:

- Lean instance arguments can be named (`[ord : Ord α]`) and used in
  the body.  Haskell evidence is anonymous unless you reify with
  `Dict`.
- Lean has `[Decidable p]` as a first-class concept: a runtime
  decision procedure attached to a *proposition*.  Haskell's closest
  is class-based `Eq`/`Ord` plus `Bool` returns; Lean's `Decidable`
  also gives you back proof or refutation, which the typechecker can
  unfold.

```lean
example : Decidable (3 < 5) := inferInstance
#eval (decide (3 < 5) : Bool)         -- true
```

**No Haskell analogue:** `Decidable` carrying both the boolean and the
proof / refutation in one structure is dependent-types specific.

## 16.6 Constraint kinds ≈ propositional types

Haskell's `-XConstraintKinds` lets you abstract over constraints:

```haskell
type Numeric a = (Num a, Eq a, Show a)
```

In Lean, you just write a `Prop`-valued definition or a structure of
instance fields:

```lean
class Numeric (α : Type) extends Add α, Mul α, BEq α, ToString α
```

`class extends` rolls all the parent instances into one ask, same
shape as Haskell's `ConstraintKinds` + tuple, but more uniform.

## 16.7 GADTs ≈ inductive families (and they're cleaner here)

Haskell GADTs let constructors *refine* the result type:

```haskell
data Expr a where
  Lit   :: Int -> Expr Int
  Plus  :: Expr Int -> Expr Int -> Expr Int
  Equal :: Expr Int -> Expr Int -> Expr Bool
```

Lean's inductive families are literally this, no extension:

```lean
inductive Expr : Type → Type where
  | lit   : Int → Expr Int
  | plus  : Expr Int → Expr Int → Expr Int
  | equal : Expr Int → Expr Int → Expr Bool

def eval : {α : Type} → Expr α → α
  | _, .lit n       => n
  | _, .plus a b    => eval a + eval b
  | _, .equal a b   => decide (eval a = eval b)

#eval eval (.plus (.lit 2) (.lit 3))          -- 5
#eval eval (.equal (.plus (.lit 2) (.lit 3)) (.lit 5))   -- true
```

Notice how the result type of `eval` depends on the constructor —
`.lit 3 : Expr Int` yields an `Int`, `.equal ... : Expr Bool` yields
a `Bool`.  Same machinery as Haskell's GADT pattern match, but the
return type is just a `match` on the constructor; no `case` magic
required.

## 16.8 Higher-kinded types

Haskell has `Functor`, `Monad`, etc. abstracted over `* -> *`.  Lean
has the same:

```lean
class MyFunctor (f : Type → Type) where
  map : (α → β) → f α → f β

instance : MyFunctor List where
  map := List.map

#eval MyFunctor.map (· + 1) [1, 2, 3]    -- [2, 3, 4]
```

The interesting part for Haskell readers: in Lean you can also have
higher-kinded *indices* without ceremony.

## 16.9 What Haskell has that Lean (mostly) doesn't

For honesty, here are Haskell type-system features without direct
Lean equivalents:

- **Type-level strings & numerals as kinds** (`Symbol`, `Nat` *as
  kinds*).  Lean has `Nat` *as a type*, and Strings *as a type*, and
  you use them directly — no separate kind.  So technically Lean
  doesn't have these as "kinds", because there's no kind hierarchy to
  put them in.  The functionality is there, just under a different
  name.
- **`OverloadedLabels`, `HasField`**.  Lean's structure projections
  and `field_proj` instances cover the same ground but with different
  ergonomics.
- **Free monads / `MonadFree` style**.  Lean's `IO` is concrete; you
  reach for `StateT`/`ReaderT` directly instead of a free interpreter
  per effect.
- **Constraint solver tricks** (`OVERLAPPING`, `INCOHERENT`).  Lean
  has instance priorities (`priority := high`) but not the full
  overlap zoo; usually you don't need it because typeclass resolution
  in Lean is more deterministic.

## 16.10 What Lean has that Haskell (mostly) doesn't

- **Full dependent types**.  Types depending on values, indexed
  families, propositional equality between values inside types — all
  first-class.  Haskell gets close with `singletons` + GADTs + type
  families but it's a workaround stack.
- **`Prop` universe** distinct from `Type`.  Proofs are erased at
  runtime; types of computational interest live elsewhere.  Haskell
  has no proof-irrelevance equivalent.
- **Tactic-mode proofs**.  `by simp`, `by exact?`, `by omega` —
  interactive proof scripts inside the file.  Haskell's nearest is
  Liquid Haskell annotations, much narrower.
- **Universe polymorphism**.  Lean tracks the universe level
  (`Type 0`, `Type 1`, …) and you can be polymorphic over it.  Haskell
  is essentially `Type 0` everywhere.

## 16.11 Where to go next

- If you came here for "GADTs but better": §16.7 + §16.4 is the
  Lean replacement for most of `DataKinds` / `GADTs` / `TypeFamilies`.
- If you want to *prove things about your types*: switch to the
  Mathlib-track tutorial (`docs/math-visual/`).
- If you want to write your own DSL with the type-level toolkit: pair
  this chapter with Ch15 (Macros) — together they cover both halves.

## 16.12 Exercises

1. Translate Haskell's `data HList :: [Type] -> Type where
   HNil :: HList '[]; HCons :: x -> HList xs -> HList (x ': xs)` to
   Lean.  Hint: use `List Type` as the index.
2. Write a Lean function `length : {n : Nat} → Vec α n → Fin (n + 1)`
   that returns the length statically known and as a runtime `Fin`.
3. (Stretch) Use §16.7's `Expr` to add a `Let` constructor with
   variable bindings, and extend `eval` accordingly.
