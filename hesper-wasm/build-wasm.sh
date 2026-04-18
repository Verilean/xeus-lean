#!/usr/bin/env bash
# build-wasm.sh - Build the Hesper Lean library for the WASM REPL.
#
# Steps:
#  1. Apply patches/*.patch onto the hesper submodule (toolchain-only fixes).
#  2. Swap in lakefile-wasm.lean (drops LSpec, native-deps, Tests, Examples).
#  3. Pin the toolchain to xeus-lean's (4.28-rc1).
#  4. Build the requested target(s) via `lake build`.
#  5. Copy the produced .olean / .ir / .ilean files into the staging dir.
#  6. Restore the submodule to a clean state.
#
# Usage:
#   build-wasm.sh <hesper-submodule-dir> <out-staging-dir> [target ...]
#
# `target` defaults to `Hesper.WGSL.DSL` (Phase 1 minimum).
set -euo pipefail

HESPER_DIR="${1:?usage: $0 <hesper-dir> <out-dir> [target ...]}"
OUT_DIR="${2:?usage: $0 <hesper-dir> <out-dir> [target ...]}"
shift 2
TARGETS=("${@:-Hesper.WGSL.DSL}")

if [ ! -f "$HESPER_DIR/Hesper.lean" ]; then
    echo "ERROR: $HESPER_DIR does not look like a Hesper checkout" >&2
    exit 1
fi

WRAP_DIR="$(cd "$(dirname "$0")" && pwd)"
PATCH_DIR="$WRAP_DIR/patches"
LAKEFILE_OVERRIDE="$WRAP_DIR/lakefile-wasm.lean"
TOOLCHAIN_FILE="$(cd "$WRAP_DIR/.." && pwd)/lean-toolchain"

mkdir -p "$OUT_DIR"

# ------------------------------------------------------------------
# 1. Save originals so we can restore even if `lake build` fails.
# ------------------------------------------------------------------
cd "$HESPER_DIR"
cp -f lakefile.lean lakefile.lean.xeus-bak 2>/dev/null || true
cp -f lakefile.toml lakefile.toml.xeus-bak 2>/dev/null || true
cp -f lean-toolchain lean-toolchain.xeus-bak 2>/dev/null || true

restore() {
    cd "$HESPER_DIR"
    [ -f lakefile.lean.xeus-bak ] && mv -f lakefile.lean.xeus-bak lakefile.lean || rm -f lakefile.lean
    [ -f lakefile.toml.xeus-bak ] && mv -f lakefile.toml.xeus-bak lakefile.toml || rm -f lakefile.toml
    [ -f lean-toolchain.xeus-bak ] && mv -f lean-toolchain.xeus-bak lean-toolchain || true
    # Roll patched files back via `git checkout` (submodule has its own .git/).
    git -C "$HESPER_DIR" checkout -- . 2>/dev/null || true
}
trap restore EXIT

# ------------------------------------------------------------------
# 2. Apply patches.
# ------------------------------------------------------------------
if [ -d "$PATCH_DIR" ]; then
    for p in "$PATCH_DIR"/*.patch; do
        [ -e "$p" ] || continue
        echo "[hesper-wasm] applying patch $(basename "$p")"
        git apply --whitespace=nowarn "$p"
    done
fi

# ------------------------------------------------------------------
# 3. Override lakefile + toolchain.
# ------------------------------------------------------------------
cp -f "$LAKEFILE_OVERRIDE" "$HESPER_DIR/lakefile.lean"
rm -f "$HESPER_DIR/lakefile.toml"           # lake prefers .toml when both exist
rm -f "$HESPER_DIR/lake-manifest.json"      # force fresh deps resolution
rm -rf "$HESPER_DIR/.lake/packages"         # forget LSpec / git deps
if [ -f "$TOOLCHAIN_FILE" ]; then
    cp -f "$TOOLCHAIN_FILE" "$HESPER_DIR/lean-toolchain"
fi

# ------------------------------------------------------------------
# 4. Build.
# ------------------------------------------------------------------
echo "[hesper-wasm] lake build ${TARGETS[*]}"
lake build "${TARGETS[@]}"

# ------------------------------------------------------------------
# 5. Stage outputs.
# ------------------------------------------------------------------
LIB="$HESPER_DIR/.lake/build/lib/lean"
IR="$HESPER_DIR/.lake/build/ir"
if [ ! -d "$LIB" ]; then
    echo "ERROR: $LIB missing — lake build produced no oleans" >&2
    exit 2
fi

mkdir -p "$OUT_DIR/Hesper"
# Copy only the kinds of files the runtime needs:
#   .olean         — kernel data
#   .olean.server  — server / metadata layer (Lean 4.28+)
#   .olean.private — private declarations
#   .ir / .ilean   — IR for runtime interpreter
# Skip .trace and .hash (build-time only).
copy_match() {
    local src="$1" rel
    [ -e "$src" ] || return 0
    rel="${src#$LIB/}"
    mkdir -p "$OUT_DIR/$(dirname "$rel")"
    cp -f "$src" "$OUT_DIR/$rel"
}

# Top-level umbrella + every Hesper/** entry of allowed extensions.
for ext in olean olean.server olean.private ir ilean; do
    [ -e "$LIB/Hesper.$ext" ] && copy_match "$LIB/Hesper.$ext"
    while IFS= read -r -d '' f; do
        copy_match "$f"
    done < <(find "$LIB/Hesper" -type f -name "*.$ext" -print0 2>/dev/null)
done

NUM=$(find "$OUT_DIR" -type f \( -name '*.olean*' -o -name '*.ir' -o -name '*.ilean' \) | wc -l)
echo "[hesper-wasm] staged $NUM files into $OUT_DIR"
