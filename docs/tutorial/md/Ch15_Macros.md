# Chapter 15 — Macros

Lean 4 is its own macro system: the surface syntax is parsed
into the same `Syntax` tree the macros manipulate, and you can
extend it without recompiling the compiler. This chapter is the
*user's* tour — enough to read other people's macros and write
small ones of your own. The full picture (elaboration, info
trees, custom tactics) lives in *Metaprogramming in Lean 4*.

## 15.1 The simplest case: `notation`

`notation` introduces new infix / prefix / postfix syntax that
expands to existing expressions:

```lean
notation:65 a " ⊕ " b => a + b + 1

#eval 10 ⊕ 20
```
```output
31
```

The `:65` is the *precedence*: how tightly the new operator
binds. Use the same number as similar built-ins (`+` is 65,
`*` is 70, etc.) to inherit familiar precedence behaviour.

`notation` is purely syntactic substitution. It can't introduce
new bindings or transform sub-terms — for those, you need
`macro`.

## 15.2 `macro` — syntax → syntax

```lean
macro "twice " e:term : term => `($e + $e)

#eval twice 21
```
```output
42
```

`macro NAME ARGS : KIND => BODY`:

- `NAME` — the keyword that triggers the macro
- `ARGS` — pattern variables (`e:term` means "match a term,
  bind it as `e`")
- `KIND` — what kind of syntax this produces (`term`,
  `command`, `tactic`, …)
- `BODY` — quoted syntax (the backtick-paren form) with `$x`
  splices

The backtick-paren `` `(...) `` is the *quotation*: "this is
syntax tree, not an expression". `$e` splices a sub-tree
captured by the pattern. The result is a fresh `Syntax` value
that Lean's elaborator then processes as if you'd typed the
expanded form.

## 15.3 Multiple arguments

```lean
macro "swapAndAdd " a:term " " b:term : term => `($b + $a)

#eval swapAndAdd 3 100
```
```output
103
```

Whitespace in the pattern (`" "` between `a:term` and `b:term`)
is significant — it's what tells the parser to expect a space
between the two arguments at the call site.

## 15.4 Custom commands

`macro` with `: command` produces top-level declarations:

```lean
macro "defConst " name:ident " := " value:term : command =>
  `(def $name : Nat := $value)

defConst answer := 42
#eval answer
```
```output
42
```

This is how the `Display` library's `#html`, `#latex`, etc.
notebook commands are defined — each is a small `macro` (or
`elab`, see below) that expands to a `Display.html ...` call.

## 15.5 Hygiene

Lean macros are **hygienic**: names you introduce in the
expansion don't accidentally capture names from the call site:

```lean
macro "withDouble " e:term : term => `(
  let x := $e + $e
  x
)

-- This `x` and the `x` inside `withDouble` are different bindings:
def callerX := 999
#eval (let x := callerX; withDouble 10)
```
```output
20
```

Without hygiene, the macro's `x` would shadow the caller's; with
hygiene, the two `x`'s are different variables.

## 15.6 `elab` — when `macro` isn't enough

`macro` is *syntactic*: it can only build new syntax trees.
When you need to inspect types, normalise terms, or emit
metadata, you reach for `elab`:

```lean
import Lean

open Lean Elab Term in
elab "sizeOfList " e:term : term => do
  let v ← elabTerm e none
  let listType ← Meta.inferType v
  -- ... in a real elaborator you'd inspect the type, generate
  -- code, etc.  For demo purposes we just emit a literal:
  let n := 0   -- placeholder
  return mkNatLit n

-- Not actually useful, just illustrating that `elab` gives you
-- the elaborator monad to play in.
```

`elab` runs in `TermElabM` (for terms) / `CommandElabM` (for
commands), where you get the full elaborator API: `Meta.inferType`,
`Meta.whnf`, `Lean.mkConst`, etc. The `xeus-lean` codebase has a
lot of small `elab` blocks; `#help_x`, `#findDecl`, `#showVerilog`
are all 5-30 line `elab` declarations.

## 15.7 Anti-quotation: `$(...)`

When you want to splice a *computed* expression (not just a
pattern variable) inside a quotation:

```lean
open Lean in
macro "naturals " n:num : term => do
  let nat := n.getNat
  let elts : Array (TSyntax `term) := (List.range nat).toArray.map fun i =>
    Syntax.mkNumLit (toString i)
  `([$elts,*])

#eval naturals 5
```
```output
[0, 1, 2, 3, 4]
```

`$elts,*` splices a comma-separated array of sub-terms into the
quotation. The patterns `$x*` (whitespace-separated) and `$x;*`
(semicolon-separated) work the same way for other separators.

## 15.8 Pattern matching on syntax

```lean
open Lean in
macro "isLiteralOne " e:term : term =>
  match e with
  | `(1) => `(true)
  | _    => `(false)

#eval isLiteralOne 1
#eval isLiteralOne 2
#eval isLiteralOne (0 + 1)   -- still false; this is `0 + 1`, not `1`
```
```output
true
false
false
```

`match e with | `pat` => ...` lets the macro inspect the input
syntax tree. The patterns are themselves backtick-paren
quotations.

## 15.9 A worked example: a tiny "if-let-else" notation

A common idiom: pattern-match an `Option`, with one branch for
"present" and one for "absent":

```lean
macro "ifSome " e:term " then " b1:term " else " b2:term : term =>
  `(match $e with
    | some x => $b1
    | none   => $b2)

-- Sadly, `x` isn't in scope of $b1 because of hygiene — the
-- caller would have to refer to it as a function:
macro "ifSome " e:term " by " f:term " else " d:term : term =>
  `(match $e with
    | some x => $f x
    | none   => $d)

#eval ifSome (some 7) by (fun n => n * 2) else 0
#eval ifSome (none : Option Nat) by (fun n => n * 2) else 0
```
```output
14
0
```

Lean's built-in `Option.elim` does this without a macro; the
example is just to show how you'd build small surface-syntax
helpers. Bigger ones (e.g. `do` itself) follow the same pattern,
just with more clauses.

## 15.10 When *not* to write a macro

- For named helpers reused 3+ times, a regular `def` is clearer
  than a `macro`.
- For "I want a different name for the same operator", `notation`
  is enough.
- For "I want to inspect *types* before generating code", reach
  for `elab` — `macro` operates purely on syntax and won't know
  what `e : Nat` vs `e : Int` looks like.
- For "I want to write a new tactic", `elab_rules : tactic` is
  the right entry point (covered in *Metaprogramming in Lean 4*).

## 15.11 Recap

You can now:

- read `notation` declarations and add your own infix operators
- write small `macro`s that desugar new keywords to existing
  syntax
- splice with `$x` and `$xs,*` inside backtick quotations
- choose between `macro` (syntax only) and `elab` (full
  elaborator access)
- recognise hygiene at work — your bindings don't leak

That's the end of this tour. From here, the natural next steps are:

- **The standard library reference**:
  <https://leanprover-community.github.io/mathlib4_docs/> for
  Mathlib, <https://leanprover.github.io/lean4/doc/> for core.
- **[Theorem Proving in Lean 4](https://leanprover.github.io/theorem_proving_in_lean4/)**
  to learn the proof side.
- **[Metaprogramming in Lean 4](https://leanprover-community.github.io/lean4-metaprogramming-book/)**
  to go deeper than this chapter on macros / elaborators / tactics.
- **xeus-lean's own [Display](../../../src/Display.lean)** module
  for ~30 small `macro` / `elab` examples (notebook commands).
