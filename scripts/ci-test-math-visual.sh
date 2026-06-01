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

# `xlean-convert --eval` shells out to `lean`.  Inside the math-tester
# image LEAN_PATH already points at /opt/lean-path (Display + Mathlib
# oleans staged at image build time).  Trust the image, but echo the
# resolved value so failing runs are debuggable.
echo "=== LEAN_PATH: ${LEAN_PATH:-unset} ==="
if [ -n "${LEAN_PATH:-}" ]; then
  echo "=== olean count under LEAN_PATH ==="
  for p in ${LEAN_PATH//:/ } ; do
    count=$(find "$p" -maxdepth 1 -name '*.olean' 2>/dev/null | wc -l)
    echo "  $p — $count olean(s)"
  done
fi

fail=0
chapters=()
# Only the math-visual tracks are gated by this job.  docs/tutorial/md
# is the Lean-as-a-language intro; some of its later chapters (type-
# level programming etc.) are deliberately illustrative-but-not-
# elaboration-clean and aren't on the math-visual contract.
for f in docs/math-visual/*/Ch*.md ; do
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
