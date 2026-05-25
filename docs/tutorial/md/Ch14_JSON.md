# Chapter 14 — JSON

`Lean.Data.Json` ships in core. It covers the parse / build /
serialise round-trip, plus the `ToJson` / `FromJson` typeclasses
that auto-derive (de)serialisation for your own types.

```lean
import Lean.Data.Json
open Lean
```

## 14.1 The `Json` type

```lean
#check (Json.null : Json)
#check (Json.num 3.14 : Json)
#check (Json.str "hi" : Json)
#check (Json.bool true : Json)
```
```output
Json.null : Json
Json.num 3.14 : Json
Json.str "hi" : Json
Json.bool true : Json
```

`Json` is a sum type: `null | bool Bool | num JsonNumber | str
String | arr (Array Json) | obj (RBNode String Json)`. You'll
rarely need to look at the constructors directly — the helper
functions cover everything.

## 14.2 Building `Json` values

```lean
#eval Json.mkObj [
  ("name",   "lean"),
  ("year",   2026),
  ("tags",   Json.arr #["language", "prover"]),
  ("nested", Json.mkObj [("k", 1), ("v", 2)])
]
```
```output
{"name": "lean", "year": 2026, "tags": ["language", "prover"], "nested": {"k": 1, "v": 2}}
```

`Json.mkObj` takes a `List (String × Json)`. Plain `String`,
`Nat`, `Int`, `Float`, and `Bool` all have `Coe` instances into
`Json`, so the bare values above work without `Json.str` /
`Json.num` wrappers.

## 14.3 Serialising — `compress` and `pretty`

```lean
def j : Json := Json.mkObj [("name", "lean"), ("year", 2026)]

#eval j.compress
#eval (j.pretty 2)
```
```output
"{\"name\":\"lean\",\"year\":2026}"
"{\n  \"name\": \"lean\",\n  \"year\": 2026\n}"
```

`compress` gives the minimal representation (good for wire
formats), `pretty n` pretty-prints with `n`-space indent (good
for files humans will read).

## 14.4 Parsing

```lean
#eval Json.parse "{\"a\": 1, \"b\": [2, 3]}"
```
```output
Except.ok {"a": 1, "b": [2, 3]}
```

`Json.parse : String → Except String Json`. Bad input yields a
parse-error message:

```lean
#eval Json.parse "{not json"
```
```output
Except.error "unexpected character at line 1, column 2: 'n'"
```

## 14.5 Drilling in — `getObjVal?` / `getArr?` etc.

```lean
def site : Json := Json.mkObj [
  ("name", "verilean"),
  ("repos", Json.arr #["xeus-lean", "sparkle", "hesper"])
]

#eval site.getObjVal? "name"
#eval site.getObjValAs? String "name"
#eval site.getObjValAs? (Array Json) "repos"
#eval site.getObjValAs? Nat "name"     -- type-coerce to Nat → fails
```
```output
Except.ok "verilean"
Except.ok "verilean"
Except.ok #["xeus-lean", "sparkle", "hesper"]
Except.error "type mismatch"
```

- `getObjVal? : Json → String → Except String Json` — raw
- `getObjValAs? : (α) → Json → String → Except String α` — typed
- `.getStr?`, `.getNat?`, `.getInt?`, `.getNum?` — direct
  extractors when the value's right there

In `do` notation, `←` short-circuits on `Except.error`:

```lean
def summarise (j : Json) : Except String String := do
  let name ← j.getObjValAs? String "name"
  let repos ← j.getObjValAs? (Array Json) "repos"
  pure s!"{name}: {repos.size} repos"

#eval summarise site
```
```output
Except.ok "verilean: 3 repos"
```

## 14.6 `ToJson` / `FromJson` — auto-derive for your records

```lean
structure User where
  id    : Nat
  name  : String
  email : String
  tags  : Array String := #[]
  deriving Repr, FromJson, ToJson

#eval (toJson ({ id := 1, name := "alice", email := "a@example.com" } : User))
```
```output
{"id": 1, "name": "alice", "email": "a@example.com", "tags": []}
```

`deriving FromJson, ToJson` generates the obvious mapping:
record fields ↔ JSON object keys, optional fields (those with
defaults) accept missing keys on parse.

Round-trip:

```lean
#eval show Except String User from do
  let j ← Json.parse "{\"id\": 1, \"name\": \"alice\", \"email\": \"a@x\"}"
  fromJson? j
```
```output
Except.ok { id := 1, name := "alice", email := "a@x", tags := #[] }
```

## 14.7 Sum types (custom encoding)

`deriving` doesn't know how you want sum types encoded
(`{"tag": "name", "value": ...}` vs `{"name": value}` vs a bare
discriminator), so for `inductive` types you write the instance:

```lean
inductive Event
  | login (user : String)
  | message (room : String) (text : String)
  | logout
  deriving Repr

instance : ToJson Event where
  toJson
    | .login u            => Json.mkObj [("op", "login"),   ("user", u)]
    | .message r t        => Json.mkObj [("op", "message"), ("room", r), ("text", t)]
    | .logout             => Json.mkObj [("op", "logout")]

#eval toJson (Event.message "lounge" "hi")
```
```output
{"op": "message", "room": "lounge", "text": "hi"}
```

The matching `FromJson` is the mirror image — dispatch on `op`
and pull out the rest of the keys.

## 14.8 Streaming JSON — line-delimited

For huge log files, JSON-per-line ("jsonl" / "ndjson") is the
common format. Lean handles it with the file streaming we saw
in Chapter 10:

```lean
#eval show IO Unit from do
  let path : System.FilePath := "/tmp/lean-tutorial.jsonl"
  IO.FS.writeFile path
    "{\"id\": 1, \"text\": \"alpha\"}\n{\"id\": 2, \"text\": \"beta\"}\n"
  let h ← IO.FS.Handle.mk path .read
  let mut count := 0
  while !(← h.isEof) do
    let line ← h.getLine
    if line.trim.isEmpty then continue
    match Json.parse line.trim with
    | .ok j  => count := count + 1
                IO.println s!"  parsed: {j.compress}"
    | .error e => IO.println s!"  parse error: {e}"
  IO.println s!"total: {count}"
```
```output
  parsed: {"id":1,"text":"alpha"}
  parsed: {"id":2,"text":"beta"}
total: 2
```

## 14.9 Recap

You can now:

- build `Json` values with `Json.mkObj` / `Json.arr` / literals
- serialise with `compress` (wire) or `pretty n` (human)
- parse with `Json.parse : String → Except String Json`
- drill in with `getObjVal?` / `getObjValAs?` / `getStr?`
- auto-`deriving FromJson, ToJson` on records
- write custom `ToJson` instances for sum types

Next: [Chapter 15 (Macros)](Ch15_Macros.md) — Lean's
metaprogramming, from a user's perspective.
