# Chapter 4 — Lists

`List` is Lean's bread-and-butter linked-list type. It's the
default sequential collection — pattern-match-friendly,
recursion-friendly, and how most standard-library APIs return
multi-valued results.

(For random-access workloads, jump ahead to [Chapter 5
(`Array`)](Ch05_Array.md). For frequent contains-tests,
[Chapter 7 (`HashMap` / `HashSet`)](Ch07_HashMap.md).)

## 4.1 Literals and basic construction

```lean
#eval [1, 2, 3]
```
```output
[1, 2, 3]
```

```lean
#check ([1, 2, 3] : List Nat)
```
```output
[1, 2, 3] : List Nat
```

The empty list is `[]`. It's polymorphic, so the type usually
comes from context:

```lean
#check ([] : List Nat)
```
```output
[] : List Nat
```

The cons operator is `::`:

```lean
#eval 0 :: [1, 2, 3]
```
```output
[0, 1, 2, 3]
```

`::` is right-associative, so `1 :: 2 :: 3 :: []` is the same as
`1 :: (2 :: (3 :: []))`, which is the same as `[1, 2, 3]`.

## 4.2 Concatenation, length, reverse

```lean
#eval [1, 2] ++ [3, 4]
#eval [1, 2, 3, 4].length
#eval [1, 2, 3, 4].reverse
```
```output
[1, 2, 3, 4]
4
[4, 3, 2, 1]
```

`++` is `O(n)` on the left operand (just like Haskell's `++`):
walks the left list, then re-uses the right one. For repeated
appends, build the list in reverse and `reverse` once at the end.

## 4.3 The functor/foldable toolbox

```lean
#eval [1, 2, 3, 4].map (· * 10)
#eval [1, 2, 3, 4].filter (· > 2)
#eval [1, 2, 3, 4].foldl (· + ·) 0
#eval [1, 2, 3, 4].sum
#eval [1, 2, 3, 4].any (· > 3)
#eval [1, 2, 3, 4].all (· > 0)
```
```output
[10, 20, 30, 40]
[3, 4]
10
10
true
true
```

The `(· ▢ ·)` syntax (two anonymous-argument placeholders) is a
shorthand for `fun a b => a ▢ b`.

`foldl` is left-fold; `foldr` exists too but be aware it forces
the entire list:

```lean
-- right-fold flips the arrow:
#eval [1, 2, 3, 4].foldr (· :: ·) ([] : List Nat)
```
```output
[1, 2, 3, 4]
```

## 4.4 Zipping and unzipping

```lean
#eval List.zip [1, 2, 3] ["a", "b", "c"]
```
```output
[(1, "a"), (2, "b"), (3, "c")]
```

`zip` stops at the shorter list. `zipWith` zips with a function:

```lean
#eval List.zipWith (· + ·) [1, 2, 3] [10, 20, 30]
```
```output
[11, 22, 33]
```

## 4.5 `Range` and friends

`List.range n` produces `[0, 1, …, n-1]`. There's no `range a b` /
`range a b step` in core, but the building blocks are easy to
combine:

```lean
#eval List.range 5
#eval (List.range 6).map (· + 1)
#eval (List.range 10).filter (· % 2 == 0)
```
```output
[0, 1, 2, 3, 4]
[1, 2, 3, 4, 5, 6]
[0, 2, 4, 6, 8]
```

## 4.6 `for ... in ... do` over lists

In `do` notation, `for x in xs do ...` iterates monadically. This
is the easiest way to combine an `IO` action with a list:

```lean
#eval show IO Unit from do
  for i in [1, 2, 3] do
    IO.println s!"item {i}"
```
```output
item 1
item 2
item 3
```

`show IO Unit from do ...` is an *ascription* that tells the
elaborator which monad the `do` runs in — needed because in a
bare `#eval do ...` the elaborator can't infer the monad from
just `for ... do IO.println` alone. With `IO.println` involved,
`IO` is the natural pick.

## 4.7 Pattern-matching on lists

```lean
def headOrZero : List Nat → Nat
  | []     => 0
  | x :: _ => x

#eval headOrZero []
#eval headOrZero [42, 7, 13]
```
```output
0
42
```

Multiple cells of pattern-matching at once:

```lean
def takePairs : List α → List (α × α)
  | a :: b :: rest => (a, b) :: takePairs rest
  | _              => []

#eval takePairs [1, 2, 3, 4, 5, 6]
#eval takePairs [1, 2, 3]
```
```output
[(1, 2), (3, 4), (5, 6)]
[(1, 2)]
```

## 4.8 `List.foldl` vs explicit recursion

For most things, the prelude already has what you want. Need a
sum / product / max / min / count? Reach for the combinator first:

```lean
#eval [3, 1, 4, 1, 5, 9, 2, 6].foldl Nat.max 0
#eval [3, 1, 4, 1, 5, 9, 2, 6].length
```
```output
9
8
```

Explicit recursion is good for *new* shapes that don't fit a
standard fold. Lean's compiler still unrolls them efficiently
when the recursion is structural.

## 4.9 `List.toArray` when you outgrow lists

Lists are great for sequential / pattern-matching workloads but
indexing `xs[100]` is `O(100)`. When you need random access, ship
the list to an `Array`:

```lean
#eval [10, 20, 30].toArray
#eval [10, 20, 30].toArray[1]!
```
```output
#[10, 20, 30]
20
```

`[i]!` is the panicking-on-OOB indexing operator; safer
alternatives are `xs[i]?` (returns `Option`) and `xs[i]` plus a
proof of `i < xs.size` (chapter 5 covers this).

## 4.10 Recap

You can now:

- build and pattern-match lists (`[]`, `::`, `[a, b, c]`)
- use `++`, `length`, `reverse`, `map`, `filter`, `foldl`,
  `zipWith`, `range`
- iterate in `do` notation with `for x in xs do ...`
- promote to `Array` when you need random access

Next: [Chapter 5 (`Array`)](Ch05_Array.md), Lean's primary
random-access container.
