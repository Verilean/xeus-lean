#!/usr/bin/env bash
# ci-build-docs.sh — run inside ghcr.io/<owner>/xeus-lean-docs-builder.
#
# Assumes the working directory is the checkout (mounted at /work)
# and that the image already contains:
#   - xlean-convert on PATH
#   - the built wasm-host pixi prefix with xlean.{js,wasm} + kernel.json
#   - /opt/xeus-lean/_olean/  ← prepacked default olean tarballs
#
# Output lands in ./_output/.
#
# Editing this script does NOT invalidate the kernel image.  Add
# new tutorial directories, change the title, tweak the --jupyterlite
# base URL — all live here.

set -euo pipefail

# ----------------------------------------------------------------------
# 0. Locate the pre-built kernel prefix and ipynb destination.
# ----------------------------------------------------------------------
PREFIX=$(pixi info -e wasm-host --json --manifest-path /opt/xeus-lean/pixi.toml \
  2>/dev/null \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['environments_info'][0]['prefix'])" \
  2>/dev/null \
  || echo "/opt/xeus-lean/.pixi/envs/wasm-host")

echo "=== PREFIX: $PREFIX ==="
ls -lh "$PREFIX/bin/" | grep xlean
cat   "$PREFIX/share/jupyter/kernels/xlean/kernel.json" | head -10

mkdir -p _output notebooks

# ----------------------------------------------------------------------
# 1. md → ipynb for tutorial chapters.
#
# Pattern: every Ch*.md under a tracked directory becomes
# notebooks/<Ch...>.ipynb (flat namespace; ChNN_Title.md uniqueness
# is the author's responsibility).
# ----------------------------------------------------------------------
gen_ipynb_for () {
  local dir="$1"
  [ -d "$dir" ] || return 0
  for f in "$dir"/Ch*.md; do
    [ -e "$f" ] || continue
    local out="notebooks/$(basename "$f" .md).ipynb"
    xlean-convert --to ipynb "$f" -o "$out"
    echo "  $f → $out"
  done
}

echo "=== Generating ipynb from md ==="
gen_ipynb_for docs/tutorial/md
for series in docs/math-visual/*/ ; do
  [ -d "$series" ] || continue
  echo "  series: $series"
  gen_ipynb_for "$series"
done

# ----------------------------------------------------------------------
# 2. JupyterLite build.
# ----------------------------------------------------------------------
echo "=== Building JupyterLite ==="
pixi run --manifest-path /opt/xeus-lean/pixi.toml -e wasm-build \
  jupyter lite build \
    --XeusAddon.prefix="$PREFIX" \
    "--XeusAddon.default_channels=[]" \
    --contents notebooks \
    --output-dir _output \
    --force

# ----------------------------------------------------------------------
# 3. Drop the prepacked olean tarballs into the site.  These came
#    from the image, so editing md never re-packs them.
# ----------------------------------------------------------------------
if [ -d /opt/xeus-lean/_olean ]; then
  echo "=== Copying olean tarballs ==="
  mkdir -p _output/xeus/wasm-host/olean
  cp /opt/xeus-lean/_olean/* _output/xeus/wasm-host/olean/
  ls -lh _output/xeus/wasm-host/olean/ | head
fi

# ----------------------------------------------------------------------
# 4. Static tutorial sites (xlean-convert --site).
# ----------------------------------------------------------------------
build_site () {
  local src="$1" out="$2" title="$3" jlite_base="$4"
  [ -d "$src" ] || { echo "  skip: $src (not present)"; return 0; }
  echo "  $src → $out  ($title)"
  xlean-convert --site "$src" \
    -o "$out" \
    --title "$title" \
    --jupyterlite-base "$jlite_base"
}

echo "=== Building static HTML sites ==="
build_site docs/tutorial/md _output/tutorial \
  "Learn Lean 4" "../lab/index.html"

for series_dir in docs/math-visual/*/ ; do
  [ -d "$series_dir" ] || continue
  series=$(basename "$series_dir")
  # Pretty title: "real-analysis" → "Real Analysis".
  title=$(echo "$series" | sed -e 's/-/ /g' \
    -e 's/\b\(.\)/\u\1/g')
  build_site "$series_dir" "_output/math-visual/$series" \
    "Visual $title" "../../lab/index.html"
done

# ----------------------------------------------------------------------
# 5. Top-level landing page that links to everything.  Generated
#    only if docs/landing.html isn't checked in; otherwise prefer
#    the author's version.
# ----------------------------------------------------------------------
if [ ! -f _output/index.html ] || [ -f docs/landing.html ]; then
  if [ -f docs/landing.html ]; then
    cp docs/landing.html _output/index.html
    echo "Used docs/landing.html as _output/index.html"
  fi
fi

echo "=== _output tree (depth 2) ==="
find _output -maxdepth 2 -type d
echo "=== Total size ==="
du -sh _output
