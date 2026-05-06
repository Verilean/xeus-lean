# Native kernel via Docker (10 minutes)

A real Lean 4 kernel running on your laptop, exposed through a local
JupyterLab. No compiling Lean from source, no NixOS, no pixi.

The native kernel doesn't have the WASM workarounds, so things that
hang in the browser (like Sparkle's `Signal.loop` interpreter path)
work normally here.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) (any modern version)
- ~8 GB free disk space (toolchain + image)

## Step 1 — Build the image

From the repo root:

```bash
docker build -f Dockerfile.native -t xeus-lean-native .
```

This takes ~5 minutes the first time. It:

1. Pulls Ubuntu 24.04
2. Installs Lean via elan (toolchain `leanprover/lean4:v4.28.0`)
3. Builds the C++ FFI library (`libxeus_ffi.a`)
4. Builds the Lean kernel (`xlean`)

## Step 2 — Run

```bash
docker run --rm -it -p 8888:8888 \
    -v "$(pwd)/notebooks:/notebooks" \
    xeus-lean-native \
    bash -c '
        # Register the kernel
        lake run installKernel
        # Pick up the notebooks volume
        cd /notebooks
        # Launch JupyterLab on all interfaces (Docker port-forwards 8888)
        pip install --break-system-packages jupyterlab >/dev/null
        jupyter lab --ip=0.0.0.0 --allow-root --no-browser
    '
```

JupyterLab prints a URL with a token — copy it into your browser. (The
URL says `127.0.0.1:8888` but the token is what matters; just paste
the whole link.)

In the launcher, pick **Lean 4** under "Notebook". Open
`rich-display.ipynb` to see what's bundled.

## Step 3 — Optional: build Sparkle

The base image only builds the kernel. To also get Sparkle's olean
files available for `import Sparkle`, do:

```bash
docker run --rm -it -p 8888:8888 \
    -v "$(pwd)/notebooks:/notebooks" \
    xeus-lean-native \
    bash -c '
        cd /app/examples/sparkle && lake update && lake build SparkleDemo
        # Make Sparkle.olean discoverable by the kernel
        export LEAN_PATH=/app/examples/sparkle/.lake/packages/sparkle/.lake/build/lib/lean:$LEAN_PATH
        cd /notebooks
        lake run --cwd /app installKernel
        pip install --break-system-packages jupyterlab >/dev/null
        jupyter lab --ip=0.0.0.0 --allow-root --no-browser
    '
```

In a notebook cell:

```lean
import Sparkle
open Sparkle.Core.Domain Sparkle.Core.Signal

def counter4 : Signal defaultDomain (BitVec 4) :=
  Signal.circuit do
    let count ← Signal.reg 0#4
    count <~ count + 1#4
    return count

-- The Signal.loop interpreter path that hangs in WASM works here.
#eval IO.println s!"counter: {counter4.val 0}"
```

## Step 4 — Optional: Hesper

The Hesper repo is wired up as a git submodule. To build its WGSL
DSL inside the container:

```bash
docker run --rm -it -v "$(pwd):/app" xeus-lean-native bash -c '
    cd /app
    git submodule update --init --recursive
    bash hesper-wasm/build-wasm.sh hesper /tmp/hesper-out \
        Hesper.WGSL.DSL Hesper.WGSL.Helpers
    ls /tmp/hesper-out/Hesper/WGSL
'
```

The full Hesper library (with WebGPU + Dawn) needs a different setup
because it builds against system Dawn — see Hesper's own README. For
the pure-Lean WGSL DSL the wrapper above is enough.

## Step 5 — Stop & clean up

`Ctrl+C` in the docker terminal stops Jupyter. Container is `--rm` so
nothing lingers. To delete the cached image:

```bash
docker rmi xeus-lean-native
```

## Workflow tip

Mounting `notebooks/` (Step 2) means edits in the browser persist on
your host filesystem — you can commit them to git, share via dropbox,
etc.

## Troubleshooting

- **"Lean 4" doesn't appear in the launcher** — the kernelspec install
  ran but JupyterLab cached the old list. Hit the refresh button on
  the launcher tab, or reload the page.
- **"Cannot find Sparkle.olean"** — you skipped Step 3. Without that
  build, only `Init`/`Std`/`Lean` are available.
- **Kernel dies on startup** — check `docker logs <container>`.
  Usually means a missing system library; the image should already
  install everything but if you customized it, add the missing dep.

## Next

- [WASM build via Docker](docker-wasm.md) — same workflow but produces
  the static JupyterLite site you can host anywhere.
- [Native build from source](native-from-source.md) — skip Docker if
  you want to hack on the kernel.
