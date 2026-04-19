#!/usr/bin/env sh
# install-kernelspec.sh - Register xlean as a Jupyter kernel.
#
# Cross-platform replacement for `lake run installKernel`, which
# hardcodes the macOS Jupyter path. Reads the host OS, picks the
# right Jupyter data dir, writes kernel.json with an absolute path
# to the freshly built `xlean` binary.
#
# Usage:
#   scripts/install-kernelspec.sh [--user|--system]
#
# --user (default): write under the per-user Jupyter data dir
# --system        : write under /usr/local/share/jupyter (needs sudo)

set -eu

scope="${1:---user}"

# Locate the built kernel binary relative to this script.
script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
xlean="$repo_root/.lake/build/bin/xlean"

if [ ! -x "$xlean" ]; then
    echo "ERROR: $xlean not found or not executable." >&2
    echo "Run \`lake build xlean\` first." >&2
    exit 1
fi

# Pick the Jupyter kernels directory.
case "$scope" in
    --user)
        case "$(uname -s)" in
            Darwin) base="$HOME/Library/Jupyter" ;;
            *)      base="${XDG_DATA_HOME:-$HOME/.local/share}/jupyter" ;;
        esac
        ;;
    --system)
        base="/usr/local/share/jupyter"
        ;;
    *)
        echo "ERROR: unknown scope '$scope'; use --user or --system" >&2
        exit 1
        ;;
esac

dest="$base/kernels/xlean"
mkdir -p "$dest"

# xlean is linked against shared libxeus / libxeus-zmq / libzmq that
# live in the cmake _deps build directory. Make them findable through
# the kernelspec's `env` so users don't need to set LD_LIBRARY_PATH
# globally.
build_libdirs="$repo_root/build-cmake/_deps/xeus-build:$repo_root/build-cmake/_deps/xeus-zmq-build:$repo_root/build-cmake/_deps/libzmq-build/lib"

case "$(uname -s)" in
    Darwin) loader_var="DYLD_LIBRARY_PATH" ;;
    *)      loader_var="LD_LIBRARY_PATH"   ;;
esac

cat > "$dest/kernel.json" <<EOF
{
  "display_name": "Lean 4",
  "argv": [
    "$xlean",
    "{connection_file}"
  ],
  "language": "lean",
  "interrupt_mode": "signal",
  "env": {
    "$loader_var": "$build_libdirs"
  }
}
EOF

echo "Installed xlean kernelspec to $dest"
echo "Verify with: jupyter kernelspec list"
