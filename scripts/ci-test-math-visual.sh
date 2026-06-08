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
  echo "=== olean inventory under LEAN_PATH ==="
  for p in ${LEAN_PATH//:/ } ; do
    count=$(find "$p" -maxdepth 1 -name '*.olean' 2>/dev/null | wc -l)
    echo "  $p — $count top-level olean(s)"
    # Dump the top-level olean filenames so we can see if Mathlib /
    # Display / Aesop / etc. actually made it into the image.
    find "$p" -maxdepth 1 -name '*.olean' 2>/dev/null | sort | sed 's|^|    |'
    # And the immediate subdirectories (Mathlib/, Aesop/, ...).
    dirs=$(find "$p" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort)
    if [ -n "$dirs" ]; then
      echo "  $p subdirs:"
      echo "$dirs" | sed 's|^|    |'
    fi
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

# Sanity check: prove `lean` can resolve the imports the chapters
# rely on.  If this 4-line smoke test can't `import Mathlib.…`,
# nothing downstream can either — better to surface the root cause
# once than have it repeat 15 times.
echo
echo "=== Sanity: resolving Mathlib imports ==="
smoke=$(mktemp --suffix=.lean)
cat > "$smoke" <<'EOF'
-- Display pulls in CommBus and a few other xeus-lean libs;
-- import it BEFORE Mathlib so a missing local dep fails fast
-- (rather than after lean has elaborated half of Mathlib).
import Display
import Mathlib.Topology.ContinuousMap.Basic
import Mathlib.Analysis.SpecialFunctions.Trigonometric.Basic
#check (Continuous : (ℝ → ℝ) → Prop)
EOF
if lean "$smoke" ; then
  echo "  Mathlib + Display reachable on LEAN_PATH"
else
  rc=$?
  echo "ERROR: smoke test couldn't even import Mathlib/Display (exit $rc)."
  echo "       LEAN_PATH=${LEAN_PATH:-unset}"
  # Drill down into what's actually present.  The most common failure
  # is "lake exe cache get pulled `Mathlib.olean` (the umbrella file
  # that triggers fetches) but no subdirectory oleans, so any
  # `import Mathlib.Topology.…` fails."
  for p in ${LEAN_PATH//:/ } ; do
    if [ -d "$p/Mathlib" ]; then
      echo "--- $p/Mathlib top-level entries ---"
      ls -la "$p/Mathlib" | head -30
      if [ -d "$p/Mathlib/Topology" ]; then
        echo "--- $p/Mathlib/Topology/ContinuousMap ---"
        ls -la "$p/Mathlib/Topology/ContinuousMap" 2>&1 | head -10
      else
        echo "    (no $p/Mathlib/Topology directory)"
      fi
      total=$(find "$p/Mathlib" -name '*.olean' 2>/dev/null | wc -l)
      echo "    Mathlib olean count under $p: $total"
    fi
  done
  rm -f "$smoke"
  exit 1
fi
rm -f "$smoke"

for f in "${chapters[@]}"; do
  echo
  echo "================================================================"
  echo "  $f"
  echo "================================================================"
  out=$(mktemp --suffix=.md)
  err=$(mktemp --suffix=.log)
  # Capture xlean-convert's own stderr (which holds the lean stdout
  # + stderr dump emitted by runEval on failure) into a file so we
  # can re-print it cleanly under the chapter header.  Without this
  # the CI log interleaves stderr from the next loop iteration and
  # it's impossible to tell which chapter failed for what reason.
  if xlean-convert --eval "$f" -o "$out" 2> "$err" ; then
    echo "  OK"
  else
    echo "  FAIL: $f"
    fail=$((fail + 1))
    echo "--- xlean-convert stderr ---"
    cat "$err" || true
    echo "--- rendered output (head) ---"
    head -80 "$out" || true
    echo "--- end of failure dump for $f ---"
  fi
  # Always echo stderr too, since `lean --run` may emit warnings
  # (e.g. `declaration uses 'sorry'`) that we want visible even on
  # successful chapters.
  if [ "${VERBOSE:-0}" = "1" ] && [ -s "$err" ]; then
    echo "--- xlean-convert stderr (verbose) ---"
    cat "$err"
  fi
  rm -f "$out" "$err"
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
