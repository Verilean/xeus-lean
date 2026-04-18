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

# Modules to bundle. Each entry is the module name (= top-level dir name in $SRC).
MODULES="Std Lean Sparkle"

# Build manifest as we go.
MANIFEST_JSON='{"version":"v2","baseUrl":"'"$BASE_URL"'","modules":{'
FIRST=1

for MOD in $MODULES; do
    if [ ! -e "$SRC/$MOD.olean" ]; then
        echo "[pack] skipping $MOD: $SRC/$MOD.olean not found" >&2
        continue
    fi

    ASSET="${MOD}-olean.tar.zst"
    OUT_TAR="$OUT/$ASSET"

    # Files: top-level Module.{olean,ir,ilean,olean.server,olean.private} + Module/**/*.{...}
    # We use --transform to keep the tarball entries as relative paths starting at the module name.
    cd "$SRC"
    PATTERNS=""
    for ext in olean olean.server olean.private ir ilean; do
        if [ -e "$MOD.$ext" ]; then
            PATTERNS="$PATTERNS $MOD.$ext"
        fi
    done
    SUBTREE_FILES=$(find "$MOD" \( \
        -name '*.olean' -o -name '*.olean.server' -o -name '*.olean.private' \
        -o -name '*.ir' -o -name '*.ilean' \) -type f 2>/dev/null || true)

    FILE_COUNT=$(printf '%s\n' $PATTERNS $SUBTREE_FILES | grep -c . || true)
    echo "[pack] $MOD: $FILE_COUNT files → $ASSET" >&2

    # Build tarball; pipe through zstd -19 (good ratio, reasonable speed).
    # GNU tar reads from stdin file list with -T -.
    {
        for p in $PATTERNS; do echo "$p"; done
        printf '%s\n' $SUBTREE_FILES
    } | tar --create --files-from=- --owner=0 --group=0 --mtime='1970-01-01' \
        | zstd -19 -T0 -o "$OUT_TAR" -f -q

    SIZE=$(stat -c '%s' "$OUT_TAR")
    echo "[pack] $MOD: $SIZE bytes (zstd -19)" >&2

    if [ $FIRST -eq 1 ]; then FIRST=0; else MANIFEST_JSON="$MANIFEST_JSON,"; fi
    MANIFEST_JSON="$MANIFEST_JSON\"$MOD\":{\"asset\":\"$ASSET\",\"size\":$SIZE,\"files\":$FILE_COUNT}"
done

MANIFEST_JSON="$MANIFEST_JSON}}"
printf '%s\n' "$MANIFEST_JSON" > "$OUT/manifest-v2.json"

echo "[pack] wrote $OUT/manifest-v2.json:" >&2
cat "$OUT/manifest-v2.json" >&2
echo "" >&2
echo "[pack] total tarball size: $(du -sh "$OUT"/*.tar.zst 2>/dev/null | tail -1 | awk '{print $1}')" >&2
