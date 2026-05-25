# Learn Lean 4 (the practical bits)

A "learn-you-a-language"-style tour of Lean 4 as a *programming
language*, with batteries-included examples for everyday tasks:
basic types and pattern matching, the standard collections,
file I/O, processes, JSON, the network, and a sprinkling of
metaprogramming at the end.

If you came here looking for theorem-proving tutorials, see
[Mathematics in Lean](https://leanprover-community.github.io/mathematics_in_lean/)
or [Theorem Proving in Lean 4](https://leanprover.github.io/theorem_proving_in_lean4/)
— those cover the proof side of the language in depth. This
tutorial complements them: same language, different audience.

Every chapter is a runnable Jupyter notebook (open in JupyterLite
or with the local `xlean` kernel). Most cells are followed by their
evaluated output as a ` ```output ` block so you can read the
chapter without firing up a kernel.

## Chapters

### Part I — Language basics
- **Ch00 — [Setup](Ch00_Setup.md)** — elan, lake, `xlean` kernel
- **Ch01 — [Values and functions](Ch01_Values.md)** — `def`, `fun`, types, `#eval` / `#check`
- **Ch02 — [Pattern matching and inductive types](Ch02_Match.md)** — `match`, `if let`, `Option`, custom enums
- **Ch03 — [Structures and type classes](Ch03_Structures.md)** — records, `Add` / `ToString` instances

### Part II — Data structures
- **Ch04 — [Lists](Ch04_List.md)** — `[]`, `::`, `map` / `filter` / `foldl`, `zipWith`, `range`
- **Ch05 — [Arrays](Ch05_Array.md)** — `#[...]`, indexing, `push` / `pop`, persistent semantics, `Id.run do`
- **Ch06 — [Strings](Ch06_String.md)** — UTF-8, `s!"..."` interpolation, iterators, padding, `toUTF8`
- **Ch07 — [`HashMap` / `HashSet` / `TreeMap`](Ch07_HashMap.md)** — keyed containers, counters, dedup
- **Ch08 — [`Option` / `Except`](Ch08_Errors.md)** — error handling without exceptions, `do` notation, `<|>`

### Part III — I/O and effects *(coming soon)*
- Ch09 — The `IO` monad and `do` notation
- Ch10 — File I/O
- Ch11 — Processes and pipes
- Ch12 — Sockets and networking
- Ch13 — `IO.Ref`, tasks, mutexes

### Part IV — Optional deeper dives *(coming soon)*
- Ch14 — JSON
- Ch15 — Macros (the `Display.*` story)

## How this is built

The chapters live as plain Markdown under `docs/tutorial/md/`. The
[`xlean-convert`](../../Convert.md) CLI converts each chapter into
the artefact you need:

```bash
# Re-evaluate the cells and bake outputs back into the .md
LEAN_PATH=$(pwd)/.lake/build/lib/lean \
  xlean-convert --eval docs/tutorial/md/Ch01_Values.md \
                -o    docs/tutorial/md/Ch01_Values.md

# Build the static HTML site
xlean-convert --site docs/tutorial/md \
              -o    _site \
              --title "Learn Lean 4"
```

That's it — same source, three target formats. See
[`docs/Convert.md`](../../Convert.md) for the full pipeline.
