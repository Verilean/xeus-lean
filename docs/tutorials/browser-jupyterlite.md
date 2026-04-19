# Try in the browser (1 minute)

The fastest way. No install, no Docker, no Lean toolchain. The whole
Lean kernel runs in your browser via WebAssembly.

## Open the deployment

<https://verilean.github.io/xeus-lean/>

You'll land on JupyterLab. Click `rich-display.ipynb` (or
`sparkle-demo.ipynb`) in the file browser on the left.

The first time you open a Lean notebook the page downloads:

- `xlean.wasm` — the kernel itself (~480 MB; cached by the browser)
- Four olean tarballs (Std, Lean, Sparkle, Hesper; ~275 MB total,
  zstd-compressed; also cached)

After that, kernel boot is ~30 seconds. Subsequent visits use the
cache and start in a few seconds.

## Run your first cell

Click the first code cell, type:

```lean
#eval 1 + 2 + 3
```

…and press **Shift+Enter**. You should see `6`.

The kernel keeps an environment across cells, so `def`s defined in
one cell are visible in later cells:

```lean
-- Cell 1
def square (x : Nat) : Nat := x * x

-- Cell 2
#eval square 7   -- 49
```

## Try the bundled libraries

`Display`, `Sparkle`, and `Hesper.WGSL.DSL` are auto-imported on the
first cell — no `import` line needed.

### Rich display

```lean
#html "<b>bold</b>"
#latex "\\int_0^1 x^2\\,dx = \\frac{1}{3}"
#md "## A heading\n\n* a list item"
#svg "<svg><circle cx='40' cy='40' r='30' fill='red'/></svg>"
```

### Sparkle (HDL)

```lean
open Sparkle.Core.Domain Sparkle.Core.Signal
#eval IO.println s!"sparkle ok"
```

### Hesper WGSL DSL

```lean
open Hesper.WGSL
def e : Exp (.scalar .f32) := Exp.var "x"
#eval IO.println e.toWGSL   -- prints: x
```

## Limitations

The browser kernel is fully Lean 4 — but a few things differ:

- **First boot is slow** (~30 s) because the WASM module and oleans
  need to download and decompress. This is one-time per browser cache
  lifetime.
- **No `import` after the first cell.** The WASM kernel reuses the
  environment from the first cell to work around a Lean memory64
  bug. Auto-imports happen up front; user `import` lines in later
  cells are ignored.
- **No native FFI extensions** (e.g. Hesper's WebGPU bridge). Only
  the pure-Lean parts of bundled libraries work.
- **No filesystem access** outside the bundled VFS.

For the full kernel, use one of the Docker / from-source tutorials.

## Sharing notebooks

JupyterLite stores notebook edits in browser storage. To share, use
**File → Download** to get the `.ipynb` and send it.

## Next

- [Native kernel via Docker](docker-native.md) — for a real Jupyter
  setup on your laptop with Sparkle simulations that actually run
  the `Signal.loop` interpreter path (not stable in WASM yet).
- [Build the WASM site yourself](docker-wasm.md) — reproduce the
  JupyterLite deployment.
