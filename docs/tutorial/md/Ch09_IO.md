# Chapter 9 — The `IO` monad and `do` notation

Lean is a pure language: a `def f : Nat → Nat` cannot read a
file, print to the screen, or query the time. Anything that
touches the outside world has type `IO α` — read as "an action
that, when run, may have side effects and produces a value of
type α".

You've already seen `IO` in passing (`IO.println`, `#eval do
IO.println ...`). This chapter lays out the model.

## 9.1 `IO Unit` — the no-result action

`IO Unit` is "an action that runs for its side effects and
produces no useful value" (`Unit` has exactly one inhabitant,
`()`). The classic example:

```lean
def hello : IO Unit := IO.println "hello, lean"

#eval hello
```
```output
hello, lean
```

`IO.println : String → IO Unit`. The action is *built* by calling
`IO.println "hello, lean"`. `#eval` then *runs* it.

`IO String`, `IO Nat`, etc. are actions that produce a value
when run.

## 9.2 `do` notation

`do` lets you sequence `IO` actions:

```lean
#eval show IO Unit from do
  IO.println "line one"
  IO.println "line two"
  IO.println "line three"
```
```output
line one
line two
line three
```

`show T from e` is an ascription; without it the elaborator has
to guess the monad type. After the first `IO.println`, the
context narrows to `IO`, so for cells like these many people
just write:

```lean
#eval do
  IO.println "first"
  IO.println "second"
```
```output
first
second
```

When there's no `IO.println` to pin the monad down — say a `do`
that just does `let x := 1; pure x` — you'll need the `show`.

## 9.3 Binding with `←`

To use the *result* of an `IO α` action you bind it with `←`:

```lean
#eval show IO Unit from do
  let now ← IO.monoMsNow
  IO.println s!"monotonic clock: {now} ms"
```
```output
monotonic clock: 12345678 ms
```

(The number you see will differ — that's the whole point of
`IO`.)

Without `←` you'd just get the *action itself*, not its result:

```lean
#eval show IO Unit from do
  let action := IO.monoMsNow    -- type: IO Nat
  let n ← action                -- runs it; n : Nat
  IO.println s!"{n}"
```
```output
12345678
```

`let x ← e` runs `e` and binds the result. `let x := e` binds a
pure value (the action itself, if `e` is `IO _`).

## 9.4 `pure` to lift a value into `IO`

```lean
def twice (msg : String) : IO String := do
  IO.println msg
  IO.println msg
  pure msg

#eval twice "echo"
```
```output
echo
echo
"echo"
```

`pure x : IO α` is an `IO` action that does nothing and produces
`x`. It's how a `do` block "returns" a value (Lean accepts `return
x` as a synonym for `pure x` inside `do`).

## 9.5 Reading user input

```lean
-- in a real terminal:
--   let line ← (← IO.getStdin).getLine
--   IO.println s!"you said: {line}"
-- in JupyterLite there's no stdin attached, so we skip this.
```

For unattended scripts, `IO.getStdin` + `IO.FS.Stream.getLine`
gives you a line. Notebooks don't have a stdin attached, so
inputs come from cell parameters instead.

## 9.6 Time and randomness

```lean
#eval show IO Unit from do
  let t1 ← IO.monoMsNow
  let _ := (List.range 100).foldl (· + ·) 0
  let t2 ← IO.monoMsNow
  IO.println s!"elapsed: {t2 - t1} ms"
```
```output
elapsed: 0 ms
```

```lean
#eval show IO Unit from do
  let n ← IO.rand 1 100
  IO.println s!"random: {n}"
```
```output
random: 42
```

`IO.monoMsNow : IO Nat` returns monotonic-clock milliseconds —
suitable for timing, never going backwards. For wall-clock time
there's `IO.Process.Stdio` + `Std.Time` (chapter 14 in this
series, once written).

`IO.rand low high : IO Nat` is a pseudo-random integer in
`[low, high]`.

## 9.7 `for ... in ... do` inside `IO`

```lean
#eval show IO Unit from do
  for i in [1, 2, 3, 4] do
    IO.println s!"i = {i}"
```
```output
i = 1
i = 2
i = 3
i = 4
```

Same syntax as on `List`/`Array` in pure code; in `IO` the body
just becomes an `IO Unit` action that's chained with the loop.

## 9.8 `let mut` and `IO.Ref`

Inside `do` you can use `let mut` for a name that you reassign.
For *real* mutable state shared across actions, use `IO.Ref`:

```lean
#eval show IO Unit from do
  let counter ← IO.mkRef 0
  for _ in [1, 2, 3] do
    counter.modify (· + 1)
  let final ← counter.get
  IO.println s!"counter = {final}"
```
```output
counter = 3
```

`IO.mkRef x : IO (IO.Ref α)`, `ref.get : IO α`, `ref.set x : IO
Unit`, `ref.modify f : IO Unit`. `IO.Ref` is the foundation for
the concurrency primitives in chapter 13.

## 9.9 Errors in `IO`

Most `IO` actions can fail — `IO.FS.readFile` if the file's
missing, `IO.Process.spawn` if the binary isn't on PATH, etc.
Failures throw `IO.Error` which bubbles up the `do` block:

```lean
#eval show IO Unit from do
  try
    let s ← IO.FS.readFile "definitely-does-not-exist.txt"
    IO.println s
  catch e =>
    IO.println s!"caught: {e}"
```
```output
caught: definitely-does-not-exist.txt: No such file or directory (error code: 2)
```

For "this command must succeed", just let the error propagate —
`#eval` (and `main`) will print it and exit non-zero. Catch only
when you intend to recover.

## 9.10 `IO` and `Except` cousins

Every `do`-friendly pattern from chapter 8 carries over:

- `←` binds the result, short-circuits on error
- `try / catch` recovers
- `<|>` tries an alternative

```lean
#eval show IO String from do
  (IO.FS.readFile "missing.txt") <|> pure "fallback content"
```
```output
"fallback content"
```

## 9.11 `IO` outside `do` — `>>=` and `>>`

`do` desugars to:

- `let x ← e; rest`  → `e >>= fun x => rest`
- `e₁; e₂`           → `e₁ >>= fun _ => e₂` (same as `e₁ >> e₂`)

Sometimes the chain reads better as operators directly:

```lean
#eval IO.println "first" >>= fun _ => IO.println "second"
```
```output
first
second
```

For one-shot logging you barely notice the difference. For
non-trivial flows `do` is clearer.

## 9.12 Recap

You can now:

- write actions of type `IO α`, `IO Unit`
- sequence them with `do`, bind with `←`, lift values with `pure`
- read clocks (`IO.monoMsNow`), make randomness (`IO.rand`)
- iterate over collections with `for ... in ... do`
- carry state across iterations with `let mut` or `IO.Ref`
- catch and recover from `IO.Error`s with `try / catch`

Next: [Chapter 10 (File I/O)](Ch10_FileIO.md) — the most common
flavour of `IO` you'll touch in everyday Lean.
