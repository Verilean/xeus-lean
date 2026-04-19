#!/usr/bin/env sh
# test-native-docker.sh - Build the Dockerfile.native image (if needed)
# and run the kernel smoke test inside it.
#
# This is the local equivalent of the CI's native-build job. Run it
# before pushing to catch breakages in:
#   * the apt package list,
#   * the libc++/glibc-C23 build flags,
#   * the kernelspec install path,
#   * the Jupyter protocol handshake.
#
# Usage:
#   scripts/test-native-docker.sh           # build + smoke
#   scripts/test-native-docker.sh --rebuild # force a fresh build
set -eu

cd "$(dirname "$0")/.."

IMG="${IMG:-xeus-lean-native}"

if [ "${1:-}" = "--rebuild" ]; then
    echo "[test-native] forcing rebuild"
    docker rmi "$IMG" 2>/dev/null || true
fi

if ! docker image inspect "$IMG" >/dev/null 2>&1; then
    echo "[test-native] building $IMG (10-15 min on first run)..."
    docker build -f Dockerfile.native -t "$IMG" .
fi

echo "[test-native] running smoke-test-native.py inside the image"
docker run --rm "$IMG" python3 scripts/smoke-test-native.py
echo "[test-native] OK"
