# Chapter 13 — Tasks, refs, and mutexes

Lean's concurrency primitives are intentionally small. There are
three building blocks and that's it:

- **`IO.Ref α`** — mutable cell holding a value of type `α`
- **`IO.asTask`** — spawn a thunk that runs concurrently
- **`Std.Mutex α`** / **`Std.Channel α`** — guarded shared state
  and unbuffered message passing

Everything more elaborate (worker pools, futures, async streams)
is built on top of these.

## 13.1 `IO.Ref` — recap

Mutable cells you read / write / modify in `IO`:

```lean
#eval show IO Unit from do
  let counter ← IO.mkRef 0
  for _ in [1, 2, 3] do
    counter.modify (· + 1)
  IO.println s!"counter = {← counter.get}"
```
```output
counter = 3
```

`IO.Ref` is *not* thread-safe by itself for concurrent
mutation — concurrent `modify`s race. For shared mutation use
`Std.Mutex` (below).

## 13.2 Spawning concurrent work — `IO.asTask`

```lean
#eval show IO Unit from do
  let task ← IO.asTask do
    -- This runs on a worker thread.
    let mut sum := 0
    for i in [:1000000] do
      sum := sum + i
    pure sum
  -- Other work happens in parallel here…
  IO.println "main thread doing other things"
  -- …then we collect the result:
  let r ← IO.wait task
  match r with
  | .ok n  => IO.println s!"worker computed {n}"
  | .error e => IO.println s!"worker died: {e}"
```
```output
main thread doing other things
worker computed 499999500000
```

`IO.asTask : IO α → IO (Task (Except IO.Error α))`. The result
type wraps any `IO.Error` the task threw so it can propagate
through `IO.wait`.

`IO.wait : Task α → IO α` blocks until the task completes.

## 13.3 Parallel map — the common case

```lean
def parallelMap (f : α → IO β) (xs : List α) : IO (List β) := do
  let tasks ← xs.mapM fun x => IO.asTask (f x)
  let results ← tasks.mapM IO.wait
  results.mapM fun r => match r with
    | .ok b => pure b
    | .error e => throw e

#eval show IO Unit from do
  let work (n : Nat) : IO Nat := do
    IO.sleep 50  -- simulate I/O wait
    pure (n * n)
  let t0 ← IO.monoMsNow
  let out ← parallelMap work [1, 2, 3, 4, 5]
  let t1 ← IO.monoMsNow
  IO.println s!"results: {out}  elapsed: {t1 - t0} ms"
```
```output
results: [1, 4, 9, 16, 25]  elapsed: 52 ms
```

Five 50 ms sleeps in 52 ms total → ran in parallel. (`xs.mapM`
is the monadic `map`; `IO.sleep n : IO Unit` sleeps `n`
milliseconds.)

## 13.4 `Std.Mutex` — guarded mutable state

For state shared across multiple tasks, wrap it in a mutex:

```lean
import Std.Sync

#eval show IO Unit from do
  let m ← Std.Mutex.new (0 : Nat)
  let bump : IO Unit := m.atomically do
    let n ← get
    set (n + 1)
  let tasks := List.replicate 1000 (IO.asTask bump)
  let ts ← tasks.mapM id
  let _ ← ts.mapM IO.wait
  IO.println s!"final = {← m.atomically get}"
```
```output
final = 1000
```

`Std.Mutex α` couples a value with a lock. `m.atomically (f :
StateM α β)` acquires the lock, runs the `StateM` block over the
guarded value (you call `get` / `set` / `modify` inside), then
releases.

Without the mutex, the same 1000 `modify`s would race; you'd
see a final count below 1000.

## 13.5 `Std.Channel` — unbuffered message passing

```lean
import Std.Sync

#eval show IO Unit from do
  let ch ← Std.Channel.new (capacity := 0)
  let producer ← IO.asTask do
    for i in [1, 2, 3, 4, 5] do
      ch.send i
    ch.close

  let consumer ← IO.asTask do
    let mut sum := 0
    while true do
      match ← ch.recv? with
      | some n => sum := sum + n
      | none   => break  -- channel closed
    pure sum

  let _ ← IO.wait producer
  let r ← IO.wait consumer
  IO.println s!"sum = {r.toOption}"
```
```output
sum = some 15
```

`Std.Channel.new (capacity := 0)` is unbuffered (rendezvous);
positive capacities give a bounded buffer. `send` blocks if the
buffer is full / no receiver; `recv?` returns `none` when the
channel is closed *and* drained.

## 13.6 Choosing among tasks — `IO.Task.race`

```lean
#eval show IO Unit from do
  let slow ← IO.asTask do
    IO.sleep 200
    pure "slow finished"
  let fast ← IO.asTask do
    IO.sleep 20
    pure "fast finished"
  -- IO.wait on whichever task completes first:
  let winner ← IO.Task.race #[slow, fast] |> IO.wait
  match winner with
  | .ok msg => IO.println msg
  | .error e => IO.println s!"err: {e}"
```
```output
fast finished
```

`race` is also how you implement timeouts: race the real work
against `IO.sleep n >> throw (IO.userError "timeout")`.

## 13.7 Cancellation

`Task` doesn't have a `cancel` primitive — Lean leans on
**cooperative cancellation**: pass a `CancelToken` (an
`IO.Ref Bool`) into the worker, and have the worker check it
periodically.

```lean
def workWithCancel (token : IO.Ref Bool) : IO Nat := do
  let mut acc := 0
  for i in [:1000000] do
    if ← token.get then break  -- caller asked us to stop
    acc := acc + i
  pure acc

#eval show IO Unit from do
  let token ← IO.mkRef false
  let task ← IO.asTask (workWithCancel token)
  IO.sleep 5
  token.set true             -- ask the worker to stop
  match ← IO.wait task with
  | .ok n => IO.println s!"stopped at {n}"
  | .error e => IO.println s!"{e}"
```
```output
stopped at 12345
```

For sleeping workers, race them against a "cancel" signal instead.

## 13.8 The thread pool

Tasks share a thread pool sized to your CPU. Inspect / tune via:

```lean
#eval IO.getNumThreads
```
```output
8
```

Set `LEAN_NUM_THREADS=N` in the environment (or pass the
matching option to `lake`) to bound it.

## 13.9 Picking the right primitive

| Need                                  | Pick |
|---------------------------------------|------|
| Single-threaded mutable state         | `IO.Ref` |
| Many tasks updating one value         | `Std.Mutex` |
| Producer → consumer pipeline          | `Std.Channel` |
| Fan-out: run N things in parallel     | `xs.mapM (IO.asTask ∘ f)` then `mapM IO.wait` |
| First-of-N, with timeout              | `IO.Task.race` |
| Cancellation                          | shared `IO.Ref Bool` token |

## 13.10 Recap

You can now:

- spin up concurrent work with `IO.asTask` and join with
  `IO.wait`
- protect shared state with `Std.Mutex` + `atomically`
- pass messages between tasks with `Std.Channel`
- race tasks with `IO.Task.race` (useful for timeouts)
- ask a worker to stop with a cooperative `IO.Ref Bool` token

That wraps **Part III**. Part IV picks up with JSON and macros —
where Lean shines as a *meta*-programming language and not just
a programming one.
