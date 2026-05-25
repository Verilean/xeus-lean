# Chapter 8 — `Option`, `Except`, and error handling

Lean (like Haskell, Rust, Swift) does errors with **values**, not
exceptions. The two workhorse types are:

- `Option α` — "maybe a value of type α", no reason given
- `Except ε α` — "either a value of type α, or an error of type ε"

`IO` adds a third: native `IO.Error`s that bubble up through
`IO` actions (we'll cover that side in [Chapter 9
(`IO`)](Ch09_IO.md)).

## 8.1 `Option` — already familiar

You met `Option` in Chapter 2. Quick refresher:

```lean
def lookup (k : String) : Option Nat :=
  if k == "one"   then some 1
  else if k == "two" then some 2
  else none

#eval lookup "two"
#eval lookup "ten"
```
```output
some 2
none
```

Consume with `match`, `if let`, or one of the helper combinators:

```lean
#eval (lookup "two").getD 0     -- with default
#eval (lookup "ten").getD 0
#eval (lookup "two").map (· * 10)
```
```output
2
0
some 20
```

## 8.2 `Except` — errors with a reason

```lean
inductive ParseError
  | empty
  | badDigit (c : Char)
  deriving Repr

def parseDigit (c : Char) : Except ParseError Nat :=
  if c.isDigit then .ok (c.toNat - '0'.toNat)
  else .error (.badDigit c)

#eval parseDigit '7'
#eval parseDigit 'x'
```
```output
Except.ok 7
Except.error (Convert.Cell.badDigit 'x')
```

(`Convert.Cell` here is just the namespace prefix the REPL prints
for the `ParseError.badDigit` constructor — `inductive` types
get a fully-qualified name. In a notebook context it shows up as
the bare name.)

Consume like `Option`:

```lean
def describe : Except ParseError Nat → String
  | .ok n          => s!"parsed {n}"
  | .error .empty  => "empty input"
  | .error (.badDigit c) => s!"bad digit: {c}"

#eval describe (parseDigit '7')
#eval describe (parseDigit 'x')
```
```output
"parsed 7"
"bad digit: x"
```

## 8.3 `do` notation works on both

`do` notation isn't just for `IO` — it works on *any* monad,
including `Option` and `Except`. This lets you write
fail-fast pipelines without nested `match`:

```lean
def parseDigits (s : String) : Except ParseError (List Nat) := do
  if s.isEmpty then .error .empty
  let mut out := []
  for c in s.toList do
    let d ← parseDigit c
    out := d :: out
  pure out.reverse

#eval parseDigits "1234"
#eval parseDigits ""
#eval parseDigits "12x4"
```
```output
Except.ok [1, 2, 3, 4]
Except.error (Convert.Cell.empty)
Except.error (Convert.Cell.badDigit 'x')
```

The `←` ("bind arrow") on `let d ← parseDigit c`:

- if `parseDigit c` is `.ok n`, binds `d := n` and continues
- if `parseDigit c` is `.error e`, the whole `do` block short-
  circuits and returns `.error e`

Same arrow, same semantics in `IO` and `Option` and `Except`.
That's the whole point of monads in user-land Lean: one syntactic
form, many error/effect models.

## 8.4 `Option`'s `do`

```lean
def addLookups (k1 k2 : String) : Option Nat := do
  let x ← lookup k1
  let y ← lookup k2
  return x + y

#eval addLookups "one" "two"
#eval addLookups "one" "ten"
```
```output
some 3
none
```

If either lookup returns `none`, the whole expression is `none`.

## 8.5 Converting between them

```lean
-- Option α → Except ε α (need to supply the error)
#eval (lookup "two").elim (.error "missing") .ok
#eval (lookup "ten").elim (.error "missing") .ok
```
```output
Except.ok 2
Except.error "missing"
```

```lean
-- Except ε α → Option α (lose the error)
#eval (parseDigit '7').toOption
#eval (parseDigit 'x').toOption
```
```output
some 7
none
```

## 8.6 `panic!` — the escape hatch

For invariants that the compiler can't check but you *know* must
hold, `panic!` aborts with a message:

```lean
def headFast (xs : List Nat) : Nat :=
  match xs with
  | x :: _ => x
  | []     => panic! "headFast: empty list"

#eval headFast [1, 2, 3]
```
```output
1
```

`panic!` is fine in code paths you can statically prove
unreachable, but every panic in tutorial-style Lean is a missing
opportunity to use `Option` or `Except` properly. Reach for
panics last.

## 8.7 `OrElse` — `<|>` for fallbacks

`Option`, `Except`, and `IO` all have `OrElse` instances. The
operator is `<|>`:

```lean
#eval lookup "ten" <|> lookup "two"
#eval parseDigit 'x' <|> parseDigit '5'
```
```output
some 2
Except.ok 5
```

Take the first success. Combine with `do`:

```lean
def parseOne (cs : List Char) : Except ParseError Nat :=
  match cs with
  | [c] => parseDigit c
  | _   => .error .empty

#eval parseOne ['7'] <|> parseOne ['x'] <|> parseOne ['3']
```
```output
Except.ok 7
```

## 8.8 `try ... catch` for `Except`

For more structured fallbacks, `try/catch` inside `do`:

```lean
#eval show Except ParseError Nat from do
  try
    let n ← parseDigit 'x'
    return n * 10
  catch _ =>
    return 0
```
```output
Except.ok 0
```

The catch handler sees the `ε` value, so you can branch on it:

```lean
#eval show Except ParseError String from do
  try
    let n ← parseDigit 'x'
    return s!"got {n}"
  catch e =>
    return s!"failed: {repr e}"
```
```output
Except.ok "failed: Convert.Cell.badDigit 'x'"
```

## 8.9 When to use what

| Situation                            | Use |
|--------------------------------------|-----|
| "Maybe absent" — no reason needed    | `Option` |
| "Failed, here's why"                 | `Except ErrType` |
| Many failure modes worth distinguishing | `Except (Inductive)` |
| Native I/O error from the runtime    | `IO α` (auto-bubbles `IO.Error`) |
| Truly impossible (invariant proved by hand) | `panic!` |

## 8.10 Recap

You can now:

- choose between `Option` and `Except` and convert between them
- use `do` notation to write fail-fast pipelines on either
- chain alternatives with `<|>`
- catch and re-throw with `try / catch` inside `do`
- save `panic!` for genuinely-unreachable code

Next: [Chapter 9 (the `IO` monad)](Ch09_IO.md), where these same
patterns extend to actual side effects.
