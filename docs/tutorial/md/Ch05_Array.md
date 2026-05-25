# Chapter 5 — Arrays

`Array α` is Lean's random-access sequence: O(1) indexing, O(1)
append at the end on average, and *persistent semantics* — it
*looks* immutable from your code, but the compiler can implement
mutations in place when the value isn't shared. This is the
container most performance-sensitive Lean code reaches for.

## 5.1 Literals

```lean
#eval #[1, 2, 3]
#check (#[1, 2, 3] : Array Nat)
```
```output
#[1, 2, 3]
#[1, 2, 3] : Array Nat
```

The `#[...]` syntax is the only difference between an `Array`
literal and a `List` literal (`[...]`). Convert either direction:

```lean
#eval #[1, 2, 3].toList
#eval [1, 2, 3].toArray
```
```output
[1, 2, 3]
#[1, 2, 3]
```

## 5.2 Indexing

```lean
#eval #[10, 20, 30][1]
```
```output
20
```

Plain `xs[i]` requires Lean to *prove* `i < xs.size` at the call
site. For literal indices on literal arrays the proof is
automatic. When the index is dynamic, three options:

```lean
def a : Array Nat := #[10, 20, 30]

-- (a) Total: returns `Option`.
#eval a[10]?
```
```output
none
```

```lean
-- (b) Panicking: aborts on out-of-bounds.
#eval a[2]!
```
```output
30
```

```lean
-- (c) With a default.
#eval a.getD 99 0    -- index 99, fallback 0
```
```output
0
```

Use `?` for safety, `!` for "this can't happen and a panic is
fine if it does", and `getD` when there's a meaningful fallback.

## 5.3 Sizing

```lean
#eval #[10, 20, 30].size
#eval (#[] : Array Nat).isEmpty
```
```output
3
true
```

## 5.4 Push / pop / concat

```lean
#eval (#[1, 2, 3].push 4)
#eval (#[1, 2, 3, 4].pop)
#eval #[1, 2] ++ #[3, 4]
```
```output
#[1, 2, 3, 4]
#[1, 2, 3]
#[1, 2, 3, 4]
```

`push` is `O(1)` amortised (just like `Vec::push` in Rust).
`pop` removes the last element — there's no `popFront` in core
because arrays aren't optimised for it; if you need a queue,
`Std.Queue` (chapter 7) is the right home.

## 5.5 Map / filter / fold

The combinator API mirrors `List`'s exactly:

```lean
#eval #[1, 2, 3, 4].map (· * 2)
#eval #[1, 2, 3, 4].filter (· > 2)
#eval #[1, 2, 3, 4].foldl (· + ·) 0
#eval #[3, 1, 4, 1, 5, 9, 2, 6].max?
```
```output
#[2, 4, 6, 8]
#[3, 4]
10
some 9
```

The `?`-suffixed variants (`max?`, `min?`, `head?`, `back?`)
return `Option` so the empty array doesn't have to panic.

## 5.6 Building with `Array.mkEmpty` + `push`

When you know roughly how big the result will be, pre-allocate:

```lean
def squares (n : Nat) : Array Nat := Id.run do
  let mut acc : Array Nat := Array.mkEmpty n
  for i in [:n] do
    acc := acc.push (i * i)
  pure acc

#eval squares 6
```
```output
#[0, 1, 4, 9, 16, 25]
```

`Id.run do` lets you use the mutable-feeling `let mut` / `for ...
do` syntax outside `IO`. Under the hood Lean threads a state
through the `Id` (identity) monad. `[:n]` is `Std.Range`'s
"`0` to `n-1`" form.

## 5.7 Persistent or in-place?

Conceptually `arr.push x` returns a *new* array. In practice, if
no one else holds a reference to `arr`, the compiler reuses its
buffer and mutates in place — this is the *uniqueness / linear
update* optimisation that makes Lean's `Array` competitive with
imperative arrays without giving up purity.

The rule of thumb: if you build an array with `let mut a := ...;
... a := a.push ...; ...` and never let it escape into another
variable until you're done, you get O(1) push.

## 5.8 `Array.foldr` and `Array.foldlIdx`

```lean
#eval #[1, 2, 3, 4].foldr (· :: ·) ([] : List Nat)
```
```output
[1, 2, 3, 4]
```

Folds with index when you need the position:

```lean
#eval (#["a", "b", "c"].mapIdx (fun i s => s!"{i}: {s}"))
```
```output
#["0: a", "1: b", "2: c"]
```

## 5.9 Slicing — `extract`

```lean
#eval #[10, 20, 30, 40, 50].extract 1 4
```
```output
#[20, 30, 40]
```

`extract start stop` returns the half-open `[start, stop)` slice
as a fresh array.

## 5.10 `Array.qsort` and `Array.toList.toString`

```lean
#eval #[3, 1, 4, 1, 5, 9, 2, 6].qsort (· < ·)
```
```output
#[1, 1, 2, 3, 4, 5, 6, 9]
```

The comparison is a `<` predicate, not an `Ordering`-returning
function — different from `List.toArray.toList` which uses
the `Ord` typeclass via `sort`.

## 5.11 When to pick `Array` over `List`

| Workload                          | Pick |
|-----------------------------------|------|
| Recursive, head/tail patterns     | `List` |
| Sequential build, no random read  | either; `List` reads nicer |
| Random access by index            | `Array` |
| Large + frequently appended       | `Array` (O(1) push) |
| Frequently `++`-ed in any position| `Array` (no copying) |
| Returned from a parser            | `Array` (xs.toArray once) |

For most "I just want a bag of things" cases, `Array` is the
right default in 2026 Lean. Lists are still the right pick when
you reach for `match` on the head.

## 5.12 Recap

You can now:

- build arrays with `#[1, 2, 3]` or `Array.mkEmpty` + `.push`
- index with `[i]` / `[i]?` / `[i]!` / `.getD i default`
- map / filter / fold just like `List`
- use `Id.run do` to build arrays imperatively without entering
  `IO`
- pick `Array` over `List` for random access and tail-append
  workloads

Next: [Chapter 6 (`String`)](Ch06_String.md), where `String` is
sneakily an `Array UInt8` under the hood — but the API hides
UTF-8 from you when you want it to.
