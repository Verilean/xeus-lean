#!/usr/bin/env bash
# Run a command inside nix-shell + pixi wasm-build environment with
# proper setup (unset nix linker flags, add binaryen to PATH).
#
# Usage: scripts/wasm-env.sh <command> [args...]
# Example: scripts/wasm-env.sh emcmake cmake -S . -B wasm-build
set -euo pipefail

if [ $# -eq 0 ]; then
    echo "Usage: $0 <command> [args...]" >&2
    exit 1
fi

# Build the inner command string, properly quoted
CMD=""
for arg in "$@"; do
    CMD+=" '${arg//\'/\'\\\'\'}'"
done

exec nix-shell -p pixi binaryen --run "
    unset LDFLAGS LDFLAGS_LD NIX_LDFLAGS 2>/dev/null || true
    BINARYEN_BIN=\$(nix-build '<nixpkgs>' -A binaryen --no-out-link 2>/dev/null)/bin
    export PATH=\$BINARYEN_BIN:\$PATH
    pixi run -e wasm-build $CMD
"
