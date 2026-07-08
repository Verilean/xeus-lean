# Chapter 17 — Coming from Haskell

If you know Haskell, Lean 4 will feel familiar — same ML-family
lineage, same emphasis on types and purity — but the differences
matter in daily use, and there is no Hackage, so *finding* an API
works differently. This chapter is a translation guide plus a
"how do I look things up" workflow.

## 17.1 Syntax and idiom, side by side

| Concept | Haskell | Lean 4 |
|---|---|---|
| define a value | `x = 1` | `def x := 1` |
| function | `f x = x + 1` | `def f x := x + 1` |
| lambda | `\x -> x + 1` | `fun x => x + 1` |
| type signature | `f :: Int -> Int` | `def f : Int → Int` |
| type application | `f @Int` | `f (α := Int)` / `@f Int` |
| algebraic data type | `data T = A \| B Int` | `inductive T \| A \| B (n : Int)` |
| record | `data P = P { x :: Int }` | `structure P where x : Int` |
| type class | `class Show a where …` | `class ToString (α) where …` |
| instance | `instance Show T where …` | `instance : ToString T where …` |
| `Maybe` | `Maybe a` / `Just` / `Nothing` | `Option α` / `some` / `none` |
| `Either` | `Either e a` / `Left` / `Right` | `Except ε α` / `.error` / `.ok` |
| list | `[1,2,3]`, `x:xs` | `[1,2,3]`, `x :: xs` |
| list map/filter | `map f xs`, `filter p xs` | `xs.map f`, `xs.filter p` |
| string interpolation | `printf` / `Text.printf` | `s!"value is {x}"` |
| `do` (monadic) | `do { x <- act; … }` | `do let x ← act; …` |
| bind / pure | `>>=` / `return` | `>>=` / `pure` (`return` also works) |
| alternative | `<|>` (Alternative) | `<|>` (`OrElse` / `Alternative`) |
| where clause | `f = … where g = …` | `where`/`let … := …` (or a top-level `def`) |
| guards | `f x \| p x = …` | `if p x then … else …` / `match` |
| newtype | `newtype N = N Int` | `structure N where val : Int` (or `def N := Int`) |

Two habits to unlearn:

- **Method syntax.** Lean leans on dot notation: `xs.map f`,
  `s.toUpper`, `arr.push x`. The function usually lives in the type's
  namespace (`List.map`, `String.toUpper`), and `x.f a` means
  `T.f x a`.
- **`→` and `∀` are first class.** `def id {α} (x : α) : α := x` —
  implicit type arguments in `{ }` are inferred, like Haskell's, but you
  can always pass them explicitly with `(α := …)`.

## 17.2 Mutation: `IORef`, `MVar`, `STRef` → `IO.Ref`, `let mut`

Haskell hides mutation behind `IORef` / `STRef` / `MVar`. Lean has the
same tools, plus an ergonomic `let mut` inside `do` (still pure —
desugars to a state-passing fold, no actual mutation escapes):

| Haskell | Lean 4 |
|---|---|
| `newIORef x` | `IO.mkRef x` |
| `readIORef r` | `r.get` |
| `writeIORef r x` | `r.set x` |
| `modifyIORef r f` | `r.modify f` |
| `runST` + `STRef` | `runST` + `ST.mkRef` |
| `MVar` (concurrency) | `Std.Mutex` / `Std.Channel` (Ch 13) |
| — (no direct analogue) | `let mut x := 0` inside `do` |

```lean
#eval show IO Nat from do
  let r ← IO.mkRef 0
  for i in [1:5] do
    r.modify (· + i)      -- 1 + 2 + 3 + 4
  r.get
```
```output
10
```

`let mut` is the one Haskell doesn't have — a loop-local mutable name
that reads like imperative code but compiles to a pure fold. Reach for
`IO.Ref` only when state must be *shared* across actions. See Ch 9 §9.8
and Ch 13 for the full story.

## 17.3 Finding an API without Hackage

There is no `cabal search` / Hackage. Instead the type *is* the search
key, and the tools are in the compiler and editor:

- **The editor (VS Code + the Lean 4 extension) is the primary docs.**
  Hover shows the type and doc-string; <kbd>F12</kbd> jumps to the
  definition; `.`-autocomplete lists everything in a type's namespace
  (type `str.` and see every `String.*`).
- **`#check` / `#print` / `#eval`** — ask the compiler directly:
  ```text
  #check   @List.foldl          -- show its full type
  #print   List.foldl           -- show its definition
  #eval    "abc".toList         -- run it
  ```
- **`exact?` / `apply?` / `rw?`** — "what function has this type?" Put
  the goal you want and let Lean search the library for you:
  ```text
  example (xs : List Nat) : List Nat := by exact?   -- suggests a fit
  ```
- **[Loogle](https://loogle.lean-lang.org)** — search the library by
  *type signature*, name substring, or a subexpression:
  `String → List Char`, `List _ → Nat`, `|- _ ++ _ = _`. This is the
  closest thing to "Hoogle for Lean".
- **[Moogle](https://moogle.ai)** — natural-language / semantic search
  over Mathlib and the stdlib.
- **Grep the source.** Every dependency is vendored under
  `.lake/packages/`; the stdlib and `Std`/`Batteries` are plain Lean
  files. `grep -r "def toUpper" .lake` finds the real definition fast.
- **Zulip** (`leanprover.zulipchat.com`) for anything the above misses.

The mindset shift: in Haskell you search Hackage for a *package*; in
Lean you already have the whole library, and you search it by *type*
(Loogle / `exact?`) or by *namespace* (editor autocomplete).

## 17.4 Where to go next

- Ch 18 — why the Lean runtime (reference counting, compiled to C)
  behaves more like C/Python than like GHC, and when that makes Lean the
  better choice for an application.
- Ch 16 — the type-level toolkit, side by side with Haskell's.
