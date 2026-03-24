#!/usr/bin/env bash
# build-native.sh — Local development build (no Docker required).
#
# Requires emsdk 5.0.3+ activated in PATH and OCCT source at $OCCT_SRC.
#
# Usage:
#   OCCT_SRC=/path/to/occt/src ./build-native.sh <config.yml>
set -euo pipefail

export OCJS_LTO="${OCJS_LTO:-0}"
export OCJS_OPT="${OCJS_OPT:--O0}"
export OCJS_JOBS="${OCJS_JOBS:-$(nproc)}"
export THREADING="${THREADING:-single-threaded}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -z "${OCCT_SRC:-}" ]; then
  echo "Error: OCCT_SRC must be set to the OCCT source directory"
  exit 1
fi

if ! command -v emcc &>/dev/null; then
  echo "Error: emcc not found. Activate emsdk first: source /path/to/emsdk/emsdk_env.sh"
  exit 1
fi

echo "=== Native dev build ==="
echo "  OCCT_SRC: ${OCCT_SRC}"
echo "  OCJS_LTO: ${OCJS_LTO}"
echo "  OCJS_OPT: ${OCJS_OPT}"
echo "  OCJS_JOBS: ${OCJS_JOBS}"

exec "${SCRIPT_DIR}/build-wasm.sh" full "$@"
