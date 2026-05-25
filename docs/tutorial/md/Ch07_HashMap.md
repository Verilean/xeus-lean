# Chapter 7 — `HashMap`, `HashSet`, `TreeMap`

For lookup-heavy workloads — caches, counters, deduplication,
"have I seen this token before?" — Lean ships three standard
containers under `Std.Data`:

- `Std.HashMap K V` — hash table keyed on any `BEq + Hashable` type
- `Std.HashSet K`  — `HashMap K Unit`, but with a tidier API
- `Std.TreeMap K V` — ordered map (red-black tree); keys need `Ord`

`HashMap` is the everyday choice. Use `TreeMap` when you need
sorted iteration or range queries.

## 7.1 `HashMap` — the basics

```lean
import Std.Data.HashMap
open Std

#eval ((HashMap.empty : HashMap String Nat).insert "a" 1).insert "b" 2
```
```output
Std.HashMap.ofList [("a", 1), ("b", 2)]
```

(The exact `#eval` rendering may shuffle entries — hash tables
have no defined iteration order. Pin order with `TreeMap` if you
need it.)

Build from a list:

```lean
def counts : HashMap String Nat :=
  HashMap.ofList [("apple", 3), ("banana", 7), ("cherry", 2)]

#eval counts
```
```output
Std.HashMap.ofList [("apple", 3), ("banana", 7), ("cherry", 2)]
```

## 7.2 Lookup

```lean
#eval counts.get? "banana"
#eval counts.get? "durian"
#eval counts.contains "apple"
#eval counts.getD "durian" 0     -- with default
```
```output
some 7
none
false
0
```

`get!` panics on miss; `get?` returns `Option`. Use `getD` (with
default) for counters / running-totals where "missing" means 0.

## 7.3 Insertion, update, removal

```lean
#eval (counts.insert "apple" 99)
#eval (counts.erase "apple")
#eval (counts.modify "apple" (· + 10))   -- works on existing keys
```
```output
Std.HashMap.ofList [("apple", 99), ("banana", 7), ("cherry", 2)]
Std.HashMap.ofList [("banana", 7), ("cherry", 2)]
Std.HashMap.ofList [("apple", 13), ("banana", 7), ("cherry", 2)]
```

`insert` overwrites if the key exists. There's no separate
"insert if absent" in core — use `if !m.contains k then m.insert k v else m`
or `m.modify k (fun v => if cond then ... else ...)` if you have
a default ready.

For "insert or accumulate" — the classic counter pattern —
combine `getD`:

```lean
def tally (xs : List String) : HashMap String Nat := Id.run do
  let mut m : HashMap String Nat := {}
  for x in xs do
    m := m.insert x (m.getD x 0 + 1)
  pure m

#eval tally ["red", "blue", "red", "green", "red", "blue"]
```
```output
Std.HashMap.ofList [("blue", 2), ("green", 1), ("red", 3)]
```

## 7.4 Iteration

```lean
#eval counts.toList
#eval counts.toList.map (·.fst)        -- keys
#eval counts.toList.map (·.snd)        -- values
```
```output
[("apple", 3), ("banana", 7), ("cherry", 2)]
["apple", "banana", "cherry"]
[3, 7, 2]
```

Or, in `do` notation:

```lean
#eval show IO Unit from do
  for (k, v) in counts do
    IO.println s!"{k} → {v}"
```
```output
apple → 3
banana → 7
cherry → 2
```

Iteration order is **not** guaranteed across runs / hash seeds.

## 7.5 `fold` for aggregations

```lean
#eval counts.fold (fun acc _ v => acc + v) 0
```
```output
12
```

`fold (f : β → K → V → β) (init : β) : β` — `K` and `V` are
separate arguments rather than a tuple, which is a hair cleaner
than `List.foldl` over `toList`.

## 7.6 `HashSet`

```lean
import Std.Data.HashSet
open Std

#eval HashSet.empty.insert 1 |>.insert 2 |>.insert 3 |>.insert 1
```
```output
Std.HashSet.ofArray #[1, 2, 3]
```

Deduplication idiom:

```lean
def unique [BEq α] [Hashable α] (xs : List α) : List α :=
  let seen := xs.foldl (·.insert ·) (HashSet.empty : HashSet α)
  seen.toList

#eval unique [3, 1, 4, 1, 5, 9, 2, 6, 5, 3, 5]
```
```output
[3, 1, 4, 5, 9, 2, 6]
```

(Order of the result follows insertion order of *first
occurrence*, but again don't rely on it.)

## 7.7 Custom key types

To use your own type as a key, derive both `BEq` and `Hashable`:

```lean
structure Coord where
  row : Nat
  col : Nat
  deriving Repr, BEq, Hashable

#eval (HashMap.empty.insert ({ row := 1, col := 2 } : Coord) "hit")
        |>.get? { row := 1, col := 2 }
```
```output
some "hit"
```

The two must agree — if `a == b` is `true` but they hash
differently the map will quietly lose entries. `deriving` makes
them consistent for you.

## 7.8 `TreeMap` — when order matters

```lean
import Std.Data.TreeMap
open Std

def sorted : TreeMap String Nat :=
  TreeMap.ofList [("zeta", 26), ("alpha", 1), ("mu", 12)]

#eval sorted.toList
```
```output
[("alpha", 1), ("mu", 12), ("zeta", 26)]
```

`TreeMap` iterates in key order, which makes it the right choice
for "give me the top-k" / "give me everything between A and Z"
queries. Lookup is `O(log n)` vs `HashMap`'s `O(1)` amortised.

## 7.9 Picking a container

| Need                              | Use |
|-----------------------------------|-----|
| Fast lookup, don't care about order | `HashMap` |
| Fast lookup, must iterate sorted    | `TreeMap` |
| "Have I seen this?"                 | `HashSet` |
| Tiny n (< ~16), no allocation       | `List (K × V)` with `.lookup` |
| Numeric keys 0..n-1                 | `Array V` |

## 7.10 Recap

You can now:

- build `HashMap`s with `.empty` + `.insert`, or `HashMap.ofList`
- read with `get?` / `getD` / `contains`
- update with `insert` / `erase` / `modify`
- iterate with `for ... in m do ...` (no ordering guarantee)
- swap to `TreeMap` when you need ordering
- derive `BEq` + `Hashable` on your own key types

Next: [Chapter 8 (`Option` / `Except` and error handling)](Ch08_Errors.md).
