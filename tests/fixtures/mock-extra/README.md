# `tests/fixtures/mock-extra/` — reference plug-in fixture

This directory is xeus-lean's **conformance test** for the
`EXTRA_WASM_DIRS` plug-in contract.  It contains the smallest
imaginable third-party Lean lib (one `@[extern]` declaration backed
by one C function) plus a build script that produces exactly the
layout xlean's CMake expects.

It is not shipped with the kernel.  It exists so that:

1. CI can prove on every push that the contract still works end-to-end.
2. Downstream library authors (Sparkle, Hesper, the next idea) have
   a copy-pasteable starting point.

If you are adding a Lean library to xeus-lean's WASM build, mirror
the four files here and adjust the names.

## Layout

```
tests/fixtures/mock-extra/
├── MockExtra.lean            -- @[extern "mock_extra_hello"] opaque mockHello
├── c_src/
│   └── mock_extra_hello.c    -- LEAN_EXPORT lean_object* mock_extra_hello(...)
├── lakefile.lean             -- one-line `lean_lib MockExtra`
├── lean-toolchain            -- pinned to match xeus-lean's
├── build-wasm.sh             -- → <staging>/{MockExtra/,lib/,xeus-lean-extra.json}
└── README.md                 -- you're here
```

## What `build-wasm.sh` produces

Pass any empty (or pre-existing) directory; the script populates it
with the staging layout xlean's CMake reads:

```
<staging>/
├── MockExtra.olean
├── MockExtra/                ← per-module olean subtree
├── lib/
│   ├── libmock_extra_wasm.a
│   └── mock_extra_exports.txt
├── .xeus-auto-imports        ← optional, registers MockExtra in cell 1
└── xeus-lean-extra.json      ← manifest the CMake EXTRA_WASM_DIRS loop reads
```

## How CI uses it

`.github/workflows/ci.yml` runs:

```yaml
- name: Build mock-extra fixture
  run: |
    pixi run -e wasm-build bash tests/fixtures/mock-extra/build-wasm.sh \
      "${RUNNER_TEMP}/mock-extra-staging"
    echo "EXTRA_WASM_DIRS=${RUNNER_TEMP}/mock-extra-staging" >> "$GITHUB_ENV"
```

then the configure step picks `EXTRA_WASM_DIRS` up:

```yaml
- name: Configure WASM build (emcmake)
  run: |
    pixi run -e wasm-build emcmake cmake -S . -B wasm-build \
      ... -DEXTRA_WASM_DIRS="${EXTRA_WASM_DIRS}"
```

and `test_wasm_node` evaluates a Lean cell that calls
`MockExtra.mockHello ()` and asserts the result is
`"hello from mock-extra"`.  If that assertion fails, the
EXTRA_WASM_DIRS contract is broken.

## What the contract guarantees

A downstream lib that follows the same layout gets:

| Thing                                | Guaranteed at link time | Guaranteed at runtime |
| ---                                  | ---                     | ---                   |
| Lean externs are reachable           | ✓ (whole-archive)       | ✓ (dlsym shim)        |
| `import MyLib` finds the olean       | ✓ (olean staged)        | ✓ (VFS / search root) |
| Module auto-imports on first cell    | ✓ (`.xeus-auto-imports`) | ✓                    |

Anything beyond that — Mathlib-bundle-style on-demand loading, JS-side
display widgets, additional `%load` namespaces — is the consumer's
responsibility.

## See also

* `README.md` of this repo, section *"Extending the kernel with your
  own Lean lib"* — the contract written out as prose.
* `CMakeLists.txt` block titled `EXTRA_WASM_DIRS` — the reader of
  `xeus-lean-extra.json`.
* `src/REPL/Frontend.lean`'s auto-import scan — the reader of
  `.xeus-auto-imports`.
