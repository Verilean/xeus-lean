#!/usr/bin/env bash
# ci-test-math-visual.sh — execute every Ch*.md via xlean-convert
# --eval and fail if any cell's #eval / example breaks.
#
# Runs inside ghcr.io/<owner>/xeus-lean-docs-builder, with the
# checkout mounted at /work and `lean` already on PATH (elan).
#
# Strategy:
#   - For each Ch*.md under docs/math-visual/<series>/ and
#     docs/tutorial/md/, run `xlean-convert --eval` into a tempfile.
#   - Print stdout/stderr.  --eval returns non-zero if `lean` exits
#     non-zero or if the rendered file fails to parse.
#   - Aggregate failures and exit non-zero at the end so one broken
#     chapter doesn't mask the others.

set -uo pipefail

# `xlean-convert --eval` shells out to `lean`.  We need LEAN_PATH to
# include the prebuilt olean tree so Display / Mathlib resolve.
PREFIX=$(pixi info -e wasm-host --json --manifest-path /opt/xeus-lean/pixi.toml \
  2>/dev/null \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['environments_info'][0]['prefix'])" \
  2>/dev/null \
  || echo "/opt/xeus-lean/.pixi/envs/wasm-host")
OLEAN_DIR="$PREFIX/share/jupyter/olean"
if [ -d "$OLEAN_DIR" ]; then
  export LEAN_PATH="${OLEAN_DIR}${LEAN_PATH:+:$LEAN_PATH}"
fi
echo "=== LEAN_PATH: ${LEAN_PATH:-unset} ==="

fail=0
chapters=()
for f in docs/math-visual/*/Ch*.md docs/tutorial/md/Ch*.md ; do
  [ -e "$f" ] || continue
  chapters+=("$f")
done

if [ "${#chapters[@]}" -eq 0 ]; then
  echo "No chapter md files found; nothing to test."
  exit 0
fi

echo "=== Will evaluate ${#chapters[@]} chapter(s) ==="
printf '  %s\n' "${chapters[@]}"

for f in "${chapters[@]}"; do
  echo
  echo "================================================================"
  echo "  $f"
  echo "================================================================"
  out=$(mktemp --suffix=.md)
  if xlean-convert --eval "$f" -o "$out"; then
    echo "  OK"
  else
    echo "  FAIL: $f"
    fail=$((fail + 1))
    # Show the first eval-output fence so the failure is debuggable
    # without re-running locally.
    head -200 "$out" || true
  fi
  rm -f "$out"
done

echo
echo "================================================================"
if [ "$fail" -eq 0 ]; then
  echo "All ${#chapters[@]} chapter(s) evaluated cleanly."
  exit 0
else
  echo "FAILED: $fail chapter(s) out of ${#chapters[@]}."
  exit 1
fi
