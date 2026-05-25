# Chapter 11 — Processes and pipes

Lean's `IO.Process` namespace covers everything from "run this
command and check the exit code" to "spawn a long-lived child
and stream stdin/stdout/stderr in parallel". It's also the
foundation for Lake's own build system.

> JupyterLite caveat: the WASM kernel has no host process model;
> `IO.Process.spawn` returns an error there. These examples work
> in the native kernel and from `lean` / `lake` on a real machine.

## 11.1 Quick: `IO.Process.run`

`IO.Process.run` is the one-shot "give me stdout" helper:

```lean
#eval show IO Unit from do
  let stdout ← IO.Process.run { cmd := "echo", args := #["hello, lean"] }
  IO.print stdout
```
```output
hello, lean
```

It throws an `IO.Error` if the child exits non-zero. For the
quick "did this succeed?" check, that's exactly what you want.

The `args` field is `Array String`. There's no shell
interpolation — `IO.Process.run` `exec`s the binary directly, no
intermediate `sh -c`.

## 11.2 With a working directory and env vars

```lean
#eval show IO Unit from do
  let out ← IO.Process.run {
    cmd := "ls"
    args := #["-la"]
    cwd := some "/tmp"
  }
  IO.println out.take 200
```
```output
total 1234
drwxrwxrwt 12 root root 4096 May 26 12:00 .
drwxr-xr-x  1 root root 4096 May  1 00:00 ..
-rw-r--r--  1 user user  …
```

```lean
#eval show IO Unit from do
  let out ← IO.Process.run {
    cmd := "printenv"
    args := #["GREETING"]
    env := #[("GREETING", some "hello"), ("UNRELATED", none)]
  }
  IO.print out
```
```output
hello
```

`env : Array (String × Option String)` is *augmentations* to the
inherited environment: `(k, some v)` sets, `(k, none)` unsets.

## 11.3 `IO.Process.output` — also get stderr and the exit code

```lean
#eval show IO Unit from do
  let r ← IO.Process.output {
    cmd := "sh"
    args := #["-c", "echo to-stdout; echo to-stderr >&2; exit 7"]
  }
  IO.println s!"exit={r.exitCode}"
  IO.println s!"stdout={r.stdout.trim}"
  IO.println s!"stderr={r.stderr.trim}"
```
```output
exit=7
stdout=to-stdout
stderr=to-stderr
```

`IO.Process.Output` is `{ exitCode : UInt32, stdout : String,
stderr : String }`. Doesn't throw on non-zero exit — you decide
how to react.

## 11.4 Streaming with `IO.Process.spawn`

For long-running children or real-time interaction, `spawn`
gives you a `Child` with handles you can read/write while the
process is still alive:

```lean
#eval show IO Unit from do
  let child ← IO.Process.spawn {
    cmd := "sh"
    args := #["-c", "for i in 1 2 3; do echo line $i; sleep 0; done"]
    stdout := .piped
    stderr := .null
  }
  let h := child.stdout
  while !(← h.isEof) do
    let line ← h.getLine
    if !line.isEmpty then
      IO.print s!"got: {line}"
  let ec ← child.wait
  IO.println s!"exit={ec}"
```
```output
got: line 1
got: line 2
got: line 3
exit=0
```

Field reference (defaults in parens):

- `cmd : String` — binary name or path
- `args : Array String` (`#[]`) — argv after argv[0]
- `cwd : Option FilePath` (`none`) — working directory
- `env : Array (String × Option String)` (`#[]`) — env tweaks
- `stdin / stdout / stderr : Stdio` (`.inherit`) — `.inherit`
  (default; child shares the parent's stream), `.piped`
  (capture, parent reads/writes), or `.null` (`/dev/null`)
- `setsid : Bool` (`false`) — new session (so signals to the
  parent don't reach the child)

## 11.5 Writing to a child's stdin

```lean
#eval show IO Unit from do
  let child ← IO.Process.spawn {
    cmd := "wc"
    args := #["-w"]
    stdin := .piped
    stdout := .piped
  }
  let stdin := child.stdin
  stdin.putStr "the quick brown fox\njumps over the lazy dog\n"
  let stdin ← IO.FS.Stream.close stdin   -- signal EOF
  -- After close we have to drop the reference so the child sees EOF.
  -- `takeStdin` returns the stream and removes it from the child record:
  let out ← child.stdout.readToEnd
  let _ ← child.wait
  IO.print out
```
```output
9
```

Two subtleties:

- The child sees EOF only after you close *your* end of the
  pipe. `IO.FS.Stream.close` does that.
- Lean's `Child` type keeps an `Option` of the stdin stream so
  you can drop the reference cleanly. The pattern above is
  good enough for shell-out style scripts.

## 11.6 Pipe two processes together

There's no built-in `|` operator; you wire two `spawn`s by hand:

```lean
#eval show IO Unit from do
  let cat ← IO.Process.spawn {
    cmd := "sh", args := #["-c", "echo banana; echo apple; echo cherry"]
    stdout := .piped
  }
  -- Read everything cat produced into a single string:
  let txt ← cat.stdout.readToEnd
  let _ ← cat.wait
  -- Then feed it to sort:
  let sorted ← IO.Process.run {
    cmd := "sort"
    stdin := .piped
    args := #[]
  } |>.bindError (fun _ => pure "")
  -- (Easier: just use IO.Process.output and supply stdin via a temp file.)
  -- For real piping with concurrent reads/writes use spawn for both
  -- ends and tee the data manually.
  IO.println sorted
```
```output

```

For most "shell out" needs, the cleanest path is one `spawn` per
process plus `let _ ← p.wait` to keep them in lock-step. Skip
the helper functions; they're easier to maintain.

A simpler real-world example — pipe through `sort`:

```lean
#eval show IO Unit from do
  let sort ← IO.Process.spawn {
    cmd := "sort"
    stdin := .piped, stdout := .piped
  }
  sort.stdin.putStr "banana\napple\ncherry\n"
  let _ ← IO.FS.Stream.close sort.stdin
  let out ← sort.stdout.readToEnd
  let _ ← sort.wait
  IO.print out
```
```output
apple
banana
cherry
```

## 11.7 Timing it

```lean
#eval show IO Unit from do
  let t0 ← IO.monoMsNow
  let _ ← IO.Process.run { cmd := "sh", args := #["-c", "sleep 0.05"] }
  let t1 ← IO.monoMsNow
  IO.println s!"elapsed: {t1 - t0} ms"
```
```output
elapsed: 51 ms
```

## 11.8 Killing a child

```lean
#eval show IO Unit from do
  let child ← IO.Process.spawn {
    cmd := "sh"
    args := #["-c", "sleep 60"]
  }
  IO.println s!"started pid={child.pid}"
  child.kill
  let _ ← child.wait
  IO.println "killed"
```
```output
started pid=12345
killed
```

`child.kill : IO Unit` sends SIGTERM (SIGKILL on Windows).
`child.wait : IO UInt32` blocks until the child exits and
returns its exit code.

## 11.9 When to reach for what

| Need                                  | Pick |
|---------------------------------------|------|
| One-shot, success expected, just stdout | `IO.Process.run` |
| One-shot, want exit code / stderr too | `IO.Process.output` |
| Long-lived, streaming                 | `IO.Process.spawn` + handles |
| Piping two long-running children      | two `spawn`s with `.piped` |

## 11.10 Recap

You can now:

- run a binary with `IO.Process.run` for the common case
- get exit code + stderr with `IO.Process.output`
- spawn long-running children with `IO.Process.spawn`
- pipe data in via `child.stdin` (close it to signal EOF)
- read out of `child.stdout` line-by-line or with `readToEnd`
- kill / wait on children

Next: [Chapter 12 (Sockets and networking)](Ch12_Network.md).
