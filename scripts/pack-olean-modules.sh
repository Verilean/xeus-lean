#!/usr/bin/env bash
# pack-olean-modules.sh - Bundle olean assets into per-module zstd tarballs.
#
# Input:   $1 = olean source dir (contains Std/, Lean/, Sparkle/, top-level Std.olean, ...)
# Output:  $2 = output dir (writes .tar.zst tarballs + manifest-v2.json)
# Optional: $3 = base URL (e.g. https://github.com/owner/repo/releases/download/vN/)
#
# Each module gets one tarball: <module>-olean.tar.zst
# Tarball entries are paths relative to /lib/lean/ (so extraction = drop into VFS).
# The top-level Module.olean lands at the root, the Module/ subtree lands under it.
#
# manifest-v2.json schema:
# {
#   "version": "v2",
#   "baseUrl": "<base url, e.g. release URL>",
#   "modules": {
#     "Std":     {"asset": "Std-olean.tar.zst",     "size": 60000000, "files": 1965},
#     "Lean":    {"asset": "Lean-olean.tar.zst",    "size": 100000000, "files": 5354},
#     "Sparkle": {"asset": "Sparkle-olean.tar.zst", "size":   6000000, "files":  797}
#   }
# }
set -eu

SRC="${1:?usage: $0 <olean-src-dir> <output-dir> [base-url]}"
OUT="${2:?usage: $0 <olean-src-dir> <output-dir> [base-url]}"
BASE_URL="${3:-}"

if [ ! -d "$SRC" ]; then
    echo "ERROR: source dir not found: $SRC" >&2
    exit 1
fi

mkdir -p "$OUT"
# Resolve to absolute paths because we `cd "$SRC"` before tar/zstd.
SRC=$(cd "$SRC" && pwd)
OUT=$(cd "$OUT" && pwd)

# Modules to bundle. Each entry is the module name (= top-level dir name in $SRC).
# Default is the always-shipped set: Init (used to be --embed-file'd into
# xlean.wasm, now a tarball for smaller WASM + faster load), Std, Lean, Sparkle,
# and the optional Hesper.
#
# Override MODULES to build a separate bundle, e.g. for Mathlib:
#   MODULES="Mathlib Aesop Batteries ImportGraph ProofWidgets4 Plausible Qq" \
#   MANIFEST_NAME=mathlib \
#     pack-olean-modules.sh $SRC $OUT
# Then post.js's loadManifestAsync('mathlib') will fetch
# `<base>manifest-mathlib.json` and the per-module tarballs alongside it.
MODULES="${MODULES:-Init Std Lean Sparkle Hesper}"
MANIFEST_NAME="${MANIFEST_NAME:-v2}"

# Build manifest as we go.
MANIFEST_JSON='{"version":"v2","baseUrl":"'"$BASE_URL"'","modules":{'
FIRST=1

for MOD in $MODULES; do
    # A "module" here is a Lean module name (dot-separated), e.g.
    # `Mathlib` or `Mathlib.Algebra`.  We translate dots to slashes
    # to map it onto the on-disk olean layout: `Mathlib.Algebra`
    # corresponds to $SRC/Mathlib/Algebra.olean (the umbrella file)
    # plus $SRC/Mathlib/Algebra/ (the per-submodule oleans).  This
    # lets us split a huge top-level bundle like Mathlib (4 GB on
    # disk, 1.3 GB zstd-19) into per-namespace chunks that each
    # stay under Chrome's worker-fetch size ceiling (~1 GB).
    MOD_PATH="${MOD//./\/}"
    if [ ! -e "$SRC/$MOD_PATH.olean" ] && \
       ! ([ -d "$SRC/$MOD_PATH" ] && find -L "$SRC/$MOD_PATH" -name '*.olean' -print -quit | grep -q .); then
        echo "[pack] skipping $MOD: no $MOD_PATH.olean and no oleans under $MOD_PATH/" >&2
        continue
    fi

    ASSET="${MOD}-olean.tar.zst"
    OUT_TAR="$OUT/$ASSET"

    # Files: top-level Module.{olean,ir,ilean,olean.server,olean.private} + Module/**/*.{...}
    # We use --transform to keep the tarball entries as relative paths starting at the module name.
    cd "$SRC"
    PATTERNS=""
    for ext in olean olean.server olean.private ir ilean; do
        if [ -e "$MOD_PATH.$ext" ]; then
            PATTERNS="$PATTERNS $MOD_PATH.$ext"
        fi
    done
    if [ -d "$MOD_PATH" ]; then
        # Exclude paths that other modules in $MODULES will pack
        # themselves.  If we list both `Mathlib.CategoryTheory` and
        # `Mathlib.CategoryTheory.Limits`, the parent's pack
        # otherwise pulls Limits/ in too and the chunk gets too big
        # all over again.  Build a list of `-not -path X/*` clauses.
        EXCLUDE_OPTS=""
        for OTHER in $MODULES; do
            [ "$OTHER" = "$MOD" ] && continue
            OTHER_PATH="${OTHER//./\/}"
            case "$OTHER_PATH" in
                "$MOD_PATH"/*)
                    EXCLUDE_OPTS="$EXCLUDE_OPTS -not ( -path $OTHER_PATH -o -path $OTHER_PATH/* )"
                    ;;
            esac
        done
        # shellcheck disable=SC2086
        SUBTREE_FILES=$(find -L "$MOD_PATH" \( \
            -name '*.olean' -o -name '*.olean.server' -o -name '*.olean.private' \
            -o -name '*.ir' -o -name '*.ilean' \) -type f \
            $EXCLUDE_OPTS 2>/dev/null || true)
    else
        SUBTREE_FILES=""
    fi

    FILE_COUNT=$(printf '%s\n' $PATTERNS $SUBTREE_FILES | grep -c . || true)
    echo "[pack] $MOD: $FILE_COUNT files → $ASSET" >&2

    # Build tarball; pipe through zstd -19 (good ratio, reasonable speed).
    # GNU tar reads from stdin file list with -T -.
    {
        for p in $PATTERNS; do echo "$p"; done
        printf '%s\n' $SUBTREE_FILES
    } | tar --create --files-from=- --dereference \
            --owner=0 --group=0 --mtime='1970-01-01' \
        | zstd -19 -T0 -f -q -c > "$OUT_TAR"

    SIZE=$(stat -c '%s' "$OUT_TAR")
    echo "[pack] $MOD: $SIZE bytes (zstd -19)" >&2

    if [ $FIRST -eq 1 ]; then FIRST=0; else MANIFEST_JSON="$MANIFEST_JSON,"; fi
    MANIFEST_JSON="$MANIFEST_JSON\"$MOD\":{\"asset\":\"$ASSET\",\"size\":$SIZE,\"files\":$FILE_COUNT}"
done

MANIFEST_JSON="$MANIFEST_JSON}}"
MANIFEST_FILE="$OUT/manifest-${MANIFEST_NAME}.json"
printf '%s\n' "$MANIFEST_JSON" > "$MANIFEST_FILE"

echo "[pack] wrote $MANIFEST_FILE:" >&2
cat "$MANIFEST_FILE" >&2
echo "" >&2
echo "[pack] total tarball size: $(du -sh "$OUT"/*.tar.zst 2>/dev/null | tail -1 | awk '{print $1}')" >&2
