# `xlean-convert` — Markdown ↔ Jupyter / Lean / HTML / docs

A CLI that splits a Markdown document into cells (Markdown vs.
fenced `lean` code), tracks each cell's evaluated outputs, and
renders the result as any of:

- a **Jupyter `.ipynb`** (with the `xeus-lean` kernel pre-set and
  cell outputs preserved),
- a **`.lean:percent`** source file you can hand to `lake build`
  for type-checking,
- a **single static HTML** page or a multi-chapter **HTML site**
  (sidebar nav, syntax-highlighted Lean, no JS evaluation), or
- the **same Markdown back** (round-trip, with outputs baked in).

It can also **run** a chapter through `lean` to capture each cell's
stdout / `Display.*` output and bake the results into a fresh
Markdown file as ` ```output:* ` fences.

## Why

Authoring directly as `.ipynb` doesn't review well — the JSON is
opaque in `git diff`, and code cells drift from `.lean` files that
`lake build` actually checks.

Authoring as `.lean:percent` (jupytext) works for `lake build`, but
jupytext doesn't ship native support for the `.lean` extension and
has no path that produces a presentable static site.

`xlean-convert` keeps the **source** in Markdown — readable on
GitHub, pretty diffs, no special tooling — and **generates**
whichever artefact you need:

```
chapter.md ─┬─→ chapter.ipynb        (--to ipynb)         JupyterLite / Lab
            ├─→ chapter.lean         (--to lean)          lake build
            ├─→ chapter.html         (--to html)          single page
            ├─→ chapter-out.md       (--eval)             outputs baked in
            └─→ _site/Ch*.html       (--site DIR)         tintin-style site
```

Round-trip:

```
chapter.md  ── --to ipynb ──→  chapter.ipynb
                                   │
                              run in Jupyter (cell outputs saved)
                                   ↓
                              chapter.ipynb
chapter.md  ←── --to md ────  (with outputs as ```output:* fences)
```

## Build

```bash
lake build xlean-convert
```

The binary lands at `.lake/build/bin/xlean-convert`.

## Usage

```text
xlean-convert --to {ipynb|lean|html|md} [-o OUTPUT] INPUT
xlean-convert --site DIR [-o OUTDIR] [--title TITLE]
xlean-convert --eval INPUT.md [-o OUTPUT.md]
```

- `--to TARGET` — one-off conversion. INPUT may be `.md`, `.markdown`,
  or `.ipynb`; the source format is auto-detected by extension.
  Use `-` for stdin (treated as Markdown).
- `-o OUTPUT` — output file (or directory for `--site`). Defaults
  to the input filename with the extension swapped. `-` = stdout.
- `--site DIR` — build a multi-chapter static HTML site (see
  *Site mode* below).
- `--title TXT` — site index title (site mode only).
- `--eval` — run the chapter through `lean` and bake every cell's
  stdout and `Display.*` output into the resulting `.md` as
  `output:*` fences (see *Eval mode* below).

### Examples

```bash
# Markdown → notebook
xlean-convert --to ipynb chapter.md

# Markdown → executable Lean source for `lake build`
xlean-convert --to lean chapter.md

# Notebook → Markdown (outputs land as ```output:* fences)
xlean-convert --to md chapter.ipynb

# Single static HTML page (no kernel)
xlean-convert --to html chapter.md

# Multi-chapter static site
xlean-convert --site docs/tutorial/md \
              -o _site \
              --title "My HDL Tutorial"

# Bake evaluation results into the Markdown
LEAN_PATH=.lake/build/lib/lean \
  xlean-convert --eval chapter.md -o chapter-out.md
```

## Cell-detection rules

The Markdown is scanned line-by-line for fenced code blocks
(` ``` `).

| Fence tag                            | Goes to |
|--------------------------------------|---------|
| `lean` (case-insensitive)            | a Jupyter **code** cell, body verbatim |
| `output` / `output:<mime/lang>`      | the **last code cell's outputs** (see below) |
| anything else (`bash`, `verilog`, `text`, …) | stays in the surrounding **Markdown** cell |
| no fence at all                      | accumulates into a Markdown cell |

### Output fences

A code cell's evaluated output is attached as one or more
` ```output[:TAG] ` fences immediately after the `lean` fence:

| Tag                | Maps to (Jupyter MIME)            | HTML render |
|--------------------|-----------------------------------|-------------|
| `output`           | `stream` (stdout)                 | `<pre class="output">` |
| `output:html`      | `text/html`                       | raw HTML inside `<div class="output html">` |
| `output:svg`       | `image/svg+xml`                   | raw SVG inside `<div class="output svg">` |
| `output:latex`     | `text/latex`                      | MathJax span |
| `output:markdown` / `output:md` | `text/markdown`     | recursively rendered |
| `output:json`      | `application/json`                | `<pre><code class="language-json">` |
| `output:<lang>` (verilog, c++, …) | `text/plain` + hljs `language-<lang>` | colourised plain text |

Multiple outputs on one cell are listed in order. Authors can
write them by hand (handy for documenting expected results) or
have `--eval` insert them automatically (see below).

Example:

````markdown
```lean
#eval 1 + 1
```
```output
2
```

```lean
#eval Display.html "<b>x</b>"
```
```output:html
<b>x</b>
```
````

## `--to lean` format

The output is a jupytext `.lean:percent`-style source: a YAML
front-matter block (in `--` Lean comments) declaring the kernel,
then alternating `-- %% [markdown]` and `-- %%` blocks. Markdown
bodies are line-prefixed with `-- ` so the file is also valid
Lean syntactically. Cell outputs are *not* preserved in this
format (use `--to md` if you need them).

## Site mode (`--site DIR`)

Walks `DIR` for `Ch*.md` and `Ch*.ipynb` (preferring `.ipynb`
when both exist for the same stem so authors can ship pre-
executed notebooks), parses each, and emits:

- `index.html` — site title + chapter list
- `Ch00_Foo.html`, `Ch01_Bar.html`, … — one page per chapter
- `style.css` — two-column layout, dark sidebar, table styling

Each chapter page has:

- **Sidebar (left)** — full chapter list, current page highlighted,
  numbers like `0`, `1b`, `10` derived by stripping the
  `Chapter N — ` prefix from each title.
- **Main column (right)** — the chapter body, with Lean code in
  `<pre><code class="language-lean">` (real Lean keywords coloured
  via the `highlightjs-lean` CDN), tables / blockquotes / lists,
  and any `output:*` fences rendered as described above.
- **Footer** — prev / Contents / next links.

The pages are fully static (no JS execution); rich outputs come
from whatever the source `.ipynb` or `.md` contains. Pages still
render cleanly if the highlight.js CDN is unreachable.

## Eval mode (`--eval`)

Runs the chapter's code cells through `lean` to capture their
stdout and `Display.*` output, then writes a fresh `.md` with the
results baked in as `output:*` fences.

The pipeline:

1. The cells are rendered as a single `.lean` file with each
   code cell followed by a delimiter `#eval` that flushes
   `Display.drain` and prints `===XLEAN-CELL-END N===`.
2. `lean FILE` is invoked (no `main` needed; `#eval` runs top-to-
   bottom). The child inherits the current `LEAN_PATH`.
3. The captured stdout is split on the delimiters, then each
   chunk is parsed for Display's MIME markers
   (`\x1bMIME:<type>\x1e<body>\x1b/MIME\x1e`). Everything outside
   markers becomes a `stream` output; each marker becomes the
   corresponding MIME output.
4. The augmented cells are serialised back to Markdown.

```bash
LEAN_PATH=.lake/build/lib/lean \
  xlean-convert --eval chapter.md -o chapter-out.md
```

**Requirements:**

- `lean` on `$PATH` (any toolchain that can build `Display`).
- `LEAN_PATH` includes the directory containing `Display.olean`
  (`.lake/build/lib/lean` after `lake build Display`).
- If the chapter uses Sparkle / Hesper / other libs, add their
  oleans to `LEAN_PATH` and include `import Sparkle` (etc.) at
  the top of the first `lean` cell.

**Not yet supported:**

- Per-cell error reporting (a failing `#eval` aborts the rest of
  the chapter; the partial outputs are still written so you can
  see where it broke).
- Interactive comms / waveform `WaveformSession.*` (those rely
  on the live Jupyter kernel; use `--to ipynb` and run in Jupyter
  for those).

## Round-trip workflow

A typical setup:

1. Author chapters as plain `.md` under `docs/tutorial/md/`.
2. Build artefacts in CI:
   ```bash
   xlean-convert --to ipynb Ch00.md -o build/Ch00.ipynb
   xlean-convert --to lean  Ch00.md -o build/Ch00.lean
   lake build BuildLean
   xlean-convert --site docs/tutorial/md -o _site --title "..."
   ```
3. Optional: bake live results into Markdown for review:
   ```bash
   LEAN_PATH=.lake/build/lib/lean \
     xlean-convert --eval Ch00.md -o docs/tutorial/md/Ch00.md
   ```
4. Deploy `_site/` to GitHub Pages.

## Testing

```bash
lake build convert-test
.lake/build/bin/convert-test
```

`src/ConvertTest.lean` runs in-memory checks covering empty input,
fence handling, the `.ipynb` JSON structure, and the
`.lean:percent` round-trip.
