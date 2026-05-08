# `xlean-convert` — Markdown → Lean / Notebook

A small CLI that splits a Markdown document into cells (Markdown vs.
fenced `lean` code) and renders them as either:

- a **Jupyter `.ipynb`** with the `xeus-lean` kernel pre-set, or
- a **`.lean:percent`** source file you can hand to `lake build` for
  type-checking.

## Why

Authoring a tutorial chapter directly as `.ipynb` works but doesn't
review well — the JSON is opaque in `git diff`, and code cells drift
from `.lean` files that `lake build` actually checks.

Authoring as `.lean:percent` (jupytext) works for `lake build`, but
jupytext doesn't ship native support for the `.lean` extension, so
authors need workarounds (file-extension trickery, YAML
metadata stripping, etc.).

`xlean-convert` keeps the **source** in Markdown — readable on
GitHub, pretty diffs, no special tooling — and **generates** both
the `.lean:percent` source for the build pipeline and the `.ipynb`
for JupyterLab.

## Build

```bash
lake build xlean-convert
```

The binary lands at `.lake/build/bin/xlean-convert`.

## Usage

```text
xlean-convert --to {ipynb|lean} [-o OUTPUT] INPUT.md
```

- `--to ipynb` (default) emits a Jupyter notebook with the
  `xeus-lean` kernel pre-set.
- `--to lean` emits a `.lean:percent` source file (kernel YAML
  header + jupytext cell delimiters).
- `-o OUTPUT` writes to that path.  Use `-` for stdout.  When
  omitted, the output filename is the input with the extension
  swapped to `.ipynb` or `.lean`.
- `INPUT` may be `-` for stdin.

### Examples

```bash
# Markdown → notebook
xlean-convert --to ipynb chapter.md
# writes chapter.ipynb in the current directory

# Markdown → executable Lean source for `lake build`
xlean-convert --to lean chapter.md
# writes chapter.lean

# Pipeline: render output cells with nbconvert
xlean-convert --to ipynb chapter.md
jupyter nbconvert --to notebook --execute --inplace \
    --ExecutePreprocessor.kernel_name=xeus-lean \
    chapter.ipynb
```

## Cell-detection rules

The Markdown is scanned line-by-line for fenced code blocks
(``` ``` ```).

| Fence tag       | Goes to             |
|-----------------|---------------------|
| `lean`          | a Jupyter **code** cell, body verbatim |
| anything else (`bash`, `verilog`, `text`, …) | stays in the surrounding **Markdown** cell as a code block |
| no fence at all | accumulates into a Markdown cell |

The choice to keep non-`lean` fences inside Markdown cells lets
authors illustrate shell commands, expected Verilog output, etc.,
without those snippets being executed.

## `--to lean` format

The output is a jupytext `.lean:percent`-style source: a YAML
front-matter block (in `--` Lean comments) declaring the kernel,
then alternating `-- %% [markdown]` and `-- %%` blocks.  The
Markdown bodies are line-prefixed with `-- ` so the file is also
valid Lean syntactically.

This makes round-tripping easy: the same `.lean` is consumed by

- `lake build` (typechecks every code cell), and
- `jupytext --to ipynb` (renders to a Jupyter notebook).

## Limitations / non-goals

- **One direction only.**  The converter is Markdown → other
  formats; it does not parse `.ipynb` or `.lean:percent` back to
  Markdown.  For round-trip authoring, jupytext's `.ipynb` ↔
  `.lean:percent` direction is already covered by jupytext itself.
- **No execution.**  Output cells in the generated `.ipynb` are
  empty.  Pipe through `jupyter nbconvert --execute` (which uses
  the `xeus-lean` kernel) to fill them.
- **Fence tag matching is case-insensitive but exact.**  ` ```Lean `
  works; ` ```lean4 ` does not.  Add new tags via the
  `Convert.parseMarkdown` source if needed.
- **No live syntax highlighting.**  The CLI just splits cells; the
  notebook viewer / kernel handles highlighting.

## Testing

```bash
lake build convert-test
.lake/build/bin/convert-test
```

The test binary (`src/ConvertTest.lean`) runs 18 in-memory checks
covering empty input, fences with various tags, the `.ipynb` JSON
structure, and the `.lean:percent` round-trip.
