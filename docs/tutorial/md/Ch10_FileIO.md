# Chapter 10 — File I/O

Files are the canonical "side effect" you'll deal with in Lean.
Everything lives under `IO.FS` ("filesystem").

> Note for JupyterLite readers: the WASM kernel ships its own
> in-memory file system. `IO.FS.writeFile "x.txt" "..."` succeeds
> but the file lives only inside the kernel process, not on your
> machine. To run these examples against real disk, use the
> native kernel (Docker image or `lean` from a terminal).

## 10.1 Whole-file read / write

```lean
def tmpPath : System.FilePath := "/tmp/lean-tutorial-hello.txt"

#eval show IO Unit from do
  IO.FS.writeFile tmpPath "hello from lean\n"
  let s ← IO.FS.readFile tmpPath
  IO.println s!"got {s.length} chars: {s}"
```
```output
got 16 chars: hello from lean
```

`IO.FS.writeFile : FilePath → String → IO Unit` truncates and
writes. `IO.FS.readFile : FilePath → IO String` reads the whole
file into memory.

For binary content, use `readBinFile` / `writeBinFile` which
work in `ByteArray`s:

```lean
#eval show IO Unit from do
  IO.FS.writeBinFile "/tmp/lean-tutorial.bin" (ByteArray.mk #[0xde, 0xad, 0xbe, 0xef])
  let bytes ← IO.FS.readBinFile "/tmp/lean-tutorial.bin"
  IO.println s!"{bytes.size} bytes: {bytes}"
```
```output
4 bytes: #[222, 173, 190, 239]
```

## 10.2 Line-by-line — `lines`

```lean
#eval show IO Unit from do
  IO.FS.writeFile "/tmp/lean-tutorial.txt" "alpha\nbeta\ngamma\n"
  let lines ← IO.FS.lines "/tmp/lean-tutorial.txt"
  for line in lines do
    IO.println s!"> {line}"
```
```output
> alpha
> beta
> gamma
```

`IO.FS.lines : FilePath → IO (Array String)` strips the trailing
newline from each line and drops the empty trailing line that a
trailing `\n` would otherwise produce.

For lazy iteration over huge files, see *Streams* below.

## 10.3 Append, exists, remove

```lean
#eval show IO Unit from do
  let p : System.FilePath := "/tmp/lean-tutorial-log.txt"
  IO.FS.writeFile p "session start\n"
  let h ← IO.FS.Handle.mk p .append
  h.putStr "line A\n"
  h.putStr "line B\n"
  IO.println (← IO.FS.readFile p)
```
```output
session start
line A
line B

```

```lean
#eval show IO Unit from do
  let p : System.FilePath := "/tmp/lean-tutorial-log.txt"
  IO.println s!"exists? {← p.pathExists}"
  IO.FS.removeFile p
  IO.println s!"exists? {← p.pathExists}"
```
```output
exists? true
exists? false
```

`System.FilePath` is the path type — it's a thin wrapper around
`String` with platform-aware concatenation via the `/` operator:

```lean
#eval ("/tmp" / "lean" / "x.txt" : System.FilePath)
```
```output
/tmp/lean/x.txt
```

## 10.4 Streams (lazy, line-by-line)

For files too large to read into a `String`, open a stream:

```lean
#eval show IO Unit from do
  IO.FS.writeFile "/tmp/lean-tutorial-big.txt"
    (String.intercalate "\n" ((List.range 10).map fun i => s!"line {i}") ++ "\n")
  let h ← IO.FS.Handle.mk "/tmp/lean-tutorial-big.txt" .read
  let mut total := 0
  while !(← h.isEof) do
    let line ← h.getLine
    if !line.isEmpty then
      total := total + 1
  IO.println s!"counted {total} lines"
```
```output
counted 10
```

`IO.FS.Handle.mk : FilePath → Mode → IO Handle`, where `Mode` is
`.read | .write | .readWrite | .append`. Other handle methods:

- `h.getLine : IO String` — reads through next `\n` (inclusive)
- `h.isEof : IO Bool` — end-of-file?
- `h.putStr : String → IO Unit` — append a chunk
- `h.flush : IO Unit` — force buffered writes
- `h.read : USize → IO ByteArray` — raw byte read
- `h.write : ByteArray → IO Unit` — raw byte write

The handle is closed automatically when it falls out of scope
(via Lean's RAII; no explicit `h.close` needed).

## 10.5 Directories

```lean
#eval show IO Unit from do
  IO.FS.createDirAll "/tmp/lean-tutorial-dir/sub"
  IO.FS.writeFile "/tmp/lean-tutorial-dir/a.txt" "A\n"
  IO.FS.writeFile "/tmp/lean-tutorial-dir/sub/b.txt" "B\n"

  let entries ← (System.FilePath.mk "/tmp/lean-tutorial-dir").readDir
  for e in entries do
    IO.println s!"{e.path} ({if ← e.path.isDir then \"dir\" else \"file\"})"
```
```output
/tmp/lean-tutorial-dir/a.txt (file)
/tmp/lean-tutorial-dir/sub (dir)
```

- `createDirAll p` — like `mkdir -p`
- `removeDir p` — empty directories only
- `removeDirAll p` — recursive remove (use with care)
- `p.readDir : IO (Array IO.FS.DirEntry)` — non-recursive listing
- `p.isDir : IO Bool`, `p.pathExists : IO Bool`

## 10.6 Walking a tree

There's no built-in `walk` in core; here's a small recursive one:

```lean
partial def walk (p : System.FilePath) : IO Unit := do
  if !(← p.pathExists) then return
  IO.println p
  if ← p.isDir then
    for e in ← p.readDir do
      walk e.path

#eval walk "/tmp/lean-tutorial-dir"
```
```output
/tmp/lean-tutorial-dir
/tmp/lean-tutorial-dir/a.txt
/tmp/lean-tutorial-dir/sub
/tmp/lean-tutorial-dir/sub/b.txt
```

`partial` tells Lean not to try to prove termination (the
filesystem might in principle be cyclic via symlinks).

## 10.7 Temporary files

`IO` doesn't ship a `mktemp` analogue out of the box; build your
own with `IO.rand`:

```lean
def newTmpDir (prefix : String) : IO System.FilePath := do
  let n ← IO.rand 1000 9999
  let p : System.FilePath := s!"/tmp/{prefix}-{n}"
  IO.FS.createDirAll p
  pure p

#eval show IO Unit from do
  let p ← newTmpDir "tutorial"
  IO.println p
  IO.FS.removeDirAll p
```
```output
/tmp/tutorial-4567
```

## 10.8 JSON in / out (quick teaser)

`Lean.Data.Json` covers both directions:

```lean
import Lean.Data.Json
open Lean

#eval show IO Unit from do
  let j : Json := Json.mkObj [("name", "lean"), ("year", 2026)]
  IO.FS.writeFile "/tmp/lean-tutorial.json" (j.pretty 2)
  let txt ← IO.FS.readFile "/tmp/lean-tutorial.json"
  IO.println txt
```
```output
{
 "name": "lean",
 "year": 2026
}
```

JSON gets its own chapter later in the series — this is just the
"yes it works out of the box" teaser.

## 10.9 Error handling on file ops

Standard `try`/`catch`:

```lean
#eval show IO String from do
  try
    IO.FS.readFile "/no/such/file.txt"
  catch e =>
    pure s!"({e})"
```
```output
"(no such file.txt: No such file or directory (error code: 2))"
```

The `IO.Error` has structured fields when you need them:

```lean
#eval show IO Unit from do
  try
    let _ ← IO.FS.readFile "/no/such/file.txt"
  catch e =>
    IO.println s!"errno: {e}"
```
```output
errno: no such file.txt: No such file or directory (error code: 2)
```

## 10.10 Recap

You can now:

- read / write whole files (`readFile`, `writeFile`, binary
  variants)
- iterate line-by-line with `IO.FS.lines` or a streaming
  `Handle`
- open streams in `.read`/`.write`/`.append` mode
- create/remove/list directories
- walk a tree with `partial def`
- catch `IO.Error` for missing-file scenarios

Next: [Chapter 11 (Processes and pipes)](Ch11_Processes.md) —
calling out to other programs.
