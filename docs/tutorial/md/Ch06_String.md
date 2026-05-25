# Chapter 6 — Strings (UTF-8, iterators)

A `String` in Lean is a UTF-8 byte buffer with a `Char`-indexed
API on top. The encoding is *visible* through positions
(`String.Pos` indexes bytes, not characters) but most everyday
operations stay at the `Char` level and stay correct under
multi-byte input.

## 6.1 Literals and basic operations

```lean
#eval "hello, lean"
#eval "hello, lean".length
#eval ("hello, lean".toList.take 5).toString
```
```output
"hello, lean"
11
"hello"
```

`String.length` counts characters (Unicode code points), not
bytes. For the byte count, use `.utf8ByteSize`:

```lean
#eval "café".length          -- 4 code points
#eval "café".utf8ByteSize    -- 5 bytes (é is 2 bytes in UTF-8)
```
```output
4
5
```

## 6.2 String interpolation: `s!"..."`

The single most useful syntax in the chapter:

```lean
def greet (name : String) (year : Nat) : String :=
  s!"hello {name}, welcome to {year}"

#eval greet "lean" 2026
```
```output
"hello lean, welcome to 2026"
```

`{x}` inside an `s!` string calls `toString x`. Any type with a
`ToString` instance works. Raw expressions can be embedded:

```lean
#eval s!"sum = {1 + 2 + 3}"
```
```output
"sum = 6"
```

For multi-line strings, ordinary `"..."` accepts embedded
newlines:

```lean
#eval "line one\nline two\nline three"
```
```output
"line one\nline two\nline three"
```

Lean's `#eval` shows the *escaped* form. If you want to see the
characters laid out, print:

```lean
#eval IO.println "line one\nline two\nline three"
```
```output
line one
line two
line three
```

## 6.3 Concatenation, contains, replace

```lean
#eval "lean " ++ "4"
#eval "lean".isEmpty
#eval "lean".contains 'a'
#eval "lean".replace "ea" "EA"
#eval "lean".toUpper
#eval " hi  ".trim
```
```output
"lean 4"
false
true
"lEAn"
"LEAN"
"hi"
```

## 6.4 Splitting and joining

```lean
#eval "a,b,c,d".splitOn ","
#eval ", ".intercalate ["x", "y", "z"]
```
```output
["a", "b", "c", "d"]
"x, y, z"
```

`splitOn` returns a `List String` (also produces a single-element
list for "no match"). For more control there's `String.split`
which takes a `Char → Bool` predicate:

```lean
#eval "  hello   world   ".split (· == ' ') |>.filter (· ≠ "")
```
```output
["hello", "world"]
```

## 6.5 Iterators — when `.length` and `[i]` aren't enough

For non-trivial scanning (lex / parse), use `String.Iterator`:

```lean
def countVowels (s : String) : Nat := Id.run do
  let mut it := s.iter
  let mut n := 0
  while !it.atEnd do
    let c := it.curr
    if "aeiouAEIOU".contains c then n := n + 1
    it := it.next
  pure n

#eval countVowels "Hello, Lean!"
```
```output
4
```

Why an iterator instead of `[i]`? Indexing a UTF-8 string at a
character position is `O(i)`: Lean has to walk from the start
counting code points. Iterators step in `O(1)` per character.

## 6.6 `String.startsWith` / `endsWith` / `find`

```lean
#eval "Lean is fun".startsWith "Lean"
#eval "main.lean".endsWith ".lean"
#eval "abcdef".find (· == 'd')
```
```output
true
true
{ byteIdx := 3 }
```

`String.find` returns a `String.Pos`, not an `Option`. End-of-
string is `s.endPos`, so test against that:

```lean
def indexOf? (s : String) (c : Char) : Option String.Pos :=
  let p := s.find (· == c)
  if p == s.endPos then none else some p

#eval indexOf? "abcdef" 'd'
#eval indexOf? "abcdef" 'z'
```
```output
some { byteIdx := 3 }
none
```

## 6.7 Numeric ↔ string

```lean
#eval (42).toString
#eval Float.toString 3.14
#eval "42".toNat!
#eval "3.14".toFloat!
#eval "not a number".toNat?    -- safe variant
```
```output
"42"
"3.140000"
42
3.140000
none
```

`toNat!` panics on bad input; `toNat?` returns `Option Nat`.
Same `!`/`?` convention as on `Array`.

## 6.8 `String.Slice` (Lean 4.28+)

Slicing without copying:

```lean
#eval "abcdefgh".extract 2 5      -- copies into new String
```
```output
"cde"
```

`String.extract a b` copies. For a view into the original
backing buffer use `String.Slice` (constructed via
`String.toSubstring` historically, now via direct slicing in
4.28). Most APIs accept `String` directly so you only reach for
slices in tight inner loops.

## 6.9 Padding and alignment

```lean
#eval s!"|{ "lean".pushn ' ' 6 }|"   -- pad to 10 chars on the right
```
```output
"|lean      |"
```

`pushn c n` appends `n` copies of character `c`. For left-pad,
build the prefix yourself or use:

```lean
def leftPad (s : String) (width : Nat) (c : Char := ' ') : String :=
  let pad := width - s.length
  if pad == 0 then s else (String.mk (List.replicate pad c)) ++ s

#eval leftPad "7" 4 '0'
#eval leftPad "256" 4 '0'
```
```output
"0007"
"0256"
```

## 6.10 Working with bytes — `String.toUTF8`

When you need the raw bytes (file I/O, network, encryption):

```lean
#eval "café".toUTF8
#eval "café".toUTF8.size
```
```output
#[99, 97, 102, 195, 169]
5
```

`String.toUTF8 : String → ByteArray`. The reverse is
`String.fromUTF8?` (returns `Option`) or `String.fromUTF8!`.

## 6.11 Recap

You can now:

- build strings with literals and `s!"..."` interpolation
- count chars (`length`) vs bytes (`utf8ByteSize`)
- `split` / `splitOn` / `intercalate` for line-y workflows
- walk strings with `String.Iterator` for O(1)-per-char scanning
- convert to/from `Nat`/`Float`/`ByteArray`
- pad and trim

Next: [Chapter 7 (`HashMap`)](Ch07_HashMap.md) — the standard
key-value containers.
