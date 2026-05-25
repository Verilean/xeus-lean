# Chapter 0 — Setup

This chapter gets you a working Lean 4 environment in three
flavours. Pick the one that matches your situation; the rest of
the tutorial works the same on all of them.

| Flavour                  | Time   | When to pick it |
|--------------------------|-------:|-----------------|
| **Browser (JupyterLite)**| 0 min  | "I just want to run the examples." Nothing to install. |
| **Docker (xeus-lean)**   | 10 sec | Local kernel, no host install of Lean. |
| **From source**          | 10 min | You want `lake`, `lean --run`, your own editor. |

## 0.1 Browser — JupyterLite

Open <https://verilean.github.io/xeus-lean/lab/index.html> in any
modern desktop browser. The xlean kernel boots in a Web Worker
(~30 s on first load while Std/Lean tarballs download), then you
get a fully-interactive Jupyter notebook with no install on the
host. State is per-tab and resets when you close the page.

This is the path to use for the rest of the tutorial if you don't
want to install anything.

## 0.2 Docker — pre-built kernel

If you have Docker, you can run the same kernel locally:

```bash
docker run --rm -it -p 8888:8888 ghcr.io/verilean/xeus-lean:latest
```

Open the URL it prints (a `127.0.0.1:8888/lab?token=...` link),
then **File → New → Notebook**, pick **Lean 4**.

The image ships the `xlean` kernel plus the `Display` library
(`#html`, `#latex`, `#svg`, `#help_x`, …). It does *not* ship
Sparkle or Hesper — those are downstream images.

## 0.3 From source — `elan` + `lake`

For the full developer experience (your own editor, `lake build`,
debugger), install Lean's toolchain manager:

```bash
curl https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh \
  -sSf | sh -s -- -y
```

Then in any project directory:

```bash
echo "leanprover/lean4:v4.28.0" > lean-toolchain
echo 'import Lake
open Lake DSL
package learn
lean_lib Learn
@[default_target] lean_exe learn where root := `Main' > lakefile.lean
mkdir -p Learn
echo 'def main : IO Unit := IO.println "hello, lean"' > Main.lean
lake build
lake exe learn
```

You should see `hello, lean`. From here you can either:

- Edit code in VS Code (install the **Lean 4** extension — it
  shares the toolchain `elan` picked up), or
- Drop into the `xlean` kernel via the Docker image above and
  use the `.lean` files alongside notebook experiments.

## 0.4 Sanity check

Open a notebook (any of the three flavours above) and run:

```lean
#eval "hello, lean 4"
```
```output
"hello, lean 4"
```

```lean
#check 1 + 1
```
```output
1 + 1 : Nat
```

If both work, you're set. On to [Chapter 1](Ch01_Values.md).
