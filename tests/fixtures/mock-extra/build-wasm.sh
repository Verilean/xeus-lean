#!/usr/bin/env bash
#
# build-wasm.sh — reference build script for a third-party Lean
# library plugging into xlean via -DEXTRA_WASM_DIRS=<staging>.
#
# This is intentionally tiny: it does exactly what the contract says
# it must do and nothing more.  Downstream builds (Sparkle, Hesper,
# future libs) can copy this layout and substitute their own
# sources.
#
# Usage:
#   build-wasm.sh <staging-dir>
#
# Produces inside <staging-dir>:
#   <staging>/MockExtra/...            ← olean tree from `lake build`
#   <staging>/MockExtra.olean          ← top-level umbrella olean
#   <staging>/lib/libmock_extra_wasm.a ← C extern compiled by emcc
#   <staging>/lib/mock_extra_exports.txt
#   <staging>/xeus-lean-extra.json     ← manifest xlean's CMake reads
#
# Run from inside an emscripten-enabled shell (`pixi run -e wasm-build …`
# in this repo) so `emcc`, `emar`, and `lake` are on PATH.

set -euo pipefail

if [ $# -ne 1 ]; then
    echo "usage: $0 <staging-dir>" >&2
    exit 2
fi

STAGING="$(realpath "$1")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$STAGING/lib"

echo "[mock-extra] staging dir : $STAGING"
echo "[mock-extra] source dir  : $SCRIPT_DIR"

# ---------------------------------------------------------------------
# 1. Build the olean tree (host Lean — same .olean works in WASM and
#    native because olean is architecture-independent for libs without
#    precompileModules).
# ---------------------------------------------------------------------
pushd "$SCRIPT_DIR" >/dev/null
lake build MockExtra
OLEAN_SRC="$SCRIPT_DIR/.lake/build/lib/lean"
if [ ! -f "$OLEAN_SRC/MockExtra.olean" ]; then
    echo "[mock-extra] ERROR: lake didn't produce $OLEAN_SRC/MockExtra.olean" >&2
    exit 1
fi
popd >/dev/null

# Copy olean(s) into the staging dir.  The umbrella file
# (<root>.olean) lives at <staging>/<root>.olean and the per-module
# tree lives at <staging>/<root>/...  This is the layout xlean's
# CMake expects when `olean_root` in the manifest is "MockExtra".
cp "$OLEAN_SRC/MockExtra.olean" "$STAGING/MockExtra.olean"
if [ -d "$OLEAN_SRC/MockExtra" ]; then
    cp -r "$OLEAN_SRC/MockExtra" "$STAGING/MockExtra"
else
    mkdir -p "$STAGING/MockExtra"
fi
# olean.private / olean.server / ir / ilean siblings, if any.
for ext in olean.private olean.server ir ilean; do
    if [ -f "$OLEAN_SRC/MockExtra.$ext" ]; then
        cp "$OLEAN_SRC/MockExtra.$ext" "$STAGING/"
    fi
done

# ---------------------------------------------------------------------
# 2. Build the C extern + the Lean-generated wrappers as a WASM
#    static library.
#
# Lake generates a `.c` file under `.lake/build/ir/MockExtra.c` that
# wraps every `@[extern]` declaration in a boxed entry point
# (`lp_<package>_<module>_<name>` / `___boxed`).  The Lean interpreter
# calls those wrappers via dlsym, so they MUST be in the archive
# alongside our hand-written C implementation.  Skipping them is the
# silent failure that shows up at runtime as
#   "Could not find native implementation of external declaration
#    'MockExtra.mockHello' (symbols 'lp_mockExtra_MockExtra_mockHello___boxed'
#    or 'lp_mockExtra_MockExtra_mockHello')"
# ---------------------------------------------------------------------
LEAN_PREFIX="$(lean --print-prefix)"
LEAN_INCLUDE="$LEAN_PREFIX/include"
if [ ! -d "$LEAN_INCLUDE" ]; then
    echo "[mock-extra] ERROR: lean toolchain include dir not found: $LEAN_INCLUDE" >&2
    exit 1
fi

GENERATED_C="$SCRIPT_DIR/.lake/build/ir/MockExtra.c"
if [ ! -f "$GENERATED_C" ]; then
    echo "[mock-extra] ERROR: lake didn't produce $GENERATED_C" >&2
    exit 1
fi

OBJ_HAND="$STAGING/lib/mock_extra_hello.o"
emcc -O2 -sMEMORY64 -fPIC \
     -I"$LEAN_INCLUDE" \
     -c "$SCRIPT_DIR/c_src/mock_extra_hello.c" \
     -o "$OBJ_HAND"

# The Lean-generated C uses C++-style declarations (`auto`, etc.) in
# some toolchains; treat it as C source but with `-Wno-everything` to
# avoid warnings turning into errors.
OBJ_LEAN="$STAGING/lib/mock_extra_lean_wrappers.o"
emcc -O2 -sMEMORY64 -fPIC -w \
     -I"$LEAN_INCLUDE" \
     -c "$GENERATED_C" \
     -o "$OBJ_LEAN"

emar rcs "$STAGING/lib/libmock_extra_wasm.a" "$OBJ_HAND" "$OBJ_LEAN"
rm -f "$OBJ_HAND" "$OBJ_LEAN"

# ---------------------------------------------------------------------
# 3. Exports file — one symbol per line, with the leading underscore
#    emscripten expects on `-sEXPORTED_FUNCTIONS`.
#
# Includes:
#   - mock_extra_hello: the hand-written C extern.
#   - every LEAN_EXPORT in the generated .c: the boxed wrappers the
#     Lean interpreter resolves via dlsym at runtime.
# ---------------------------------------------------------------------
EXPORTS="$STAGING/lib/mock_extra_exports.txt"
{
    echo "_mock_extra_hello"
    # Pick up `LEAN_EXPORT <type> <name>(` lines from the generated C.
    # Match both bare names and the `___boxed` form Lean uses.
    grep -oE 'LEAN_EXPORT[[:space:]]+[a-zA-Z_][a-zA-Z_0-9*]*[[:space:]]+[a-zA-Z_][a-zA-Z_0-9]*[[:space:]]*\(' \
         "$GENERATED_C" \
      | sed -E 's/^LEAN_EXPORT[[:space:]]+[a-zA-Z_][a-zA-Z_0-9*]*[[:space:]]+([a-zA-Z_][a-zA-Z_0-9]*).*/_\1/'
} | sort -u > "$EXPORTS"

EXPORT_COUNT=$(wc -l < "$EXPORTS")
echo "[mock-extra] $EXPORT_COUNT symbol(s) → $EXPORTS"

# ---------------------------------------------------------------------
# 4. xeus-lean-extra.json — the contract xlean's CMake reads.
# ---------------------------------------------------------------------
cat > "$STAGING/xeus-lean-extra.json" <<'EOF'
{
  "archive":    "lib/libmock_extra_wasm.a",
  "exports":    "lib/mock_extra_exports.txt",
  "olean_root": "MockExtra"
}
EOF

# ---------------------------------------------------------------------
# 5. Optional: drop a .xeus-auto-imports registry so xlean's REPL
#    pre-imports MockExtra on the first cell.  Lives at the olean
#    root because xlean's auto-import scan walks each search root.
# ---------------------------------------------------------------------
cat > "$STAGING/.xeus-auto-imports" <<'EOF'
# Modules to inject into cell 1 of the xlean REPL.
# One module name per line; lines starting with # are ignored.
MockExtra
EOF

echo "[mock-extra] DONE.  Pass this to xlean's WASM build with:"
echo "             -DEXTRA_WASM_DIRS=\"$STAGING\""
