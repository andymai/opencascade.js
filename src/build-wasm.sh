#!/usr/bin/env bash
# build-wasm.sh — Unified WASM build script for opencascade.js
#
# Usage:
#   build-wasm.sh pch                    Generate precompiled header
#   build-wasm.sh compile [threading]    Compile OCCT sources + bindings to .o
#   build-wasm.sh link <config.yml>      Link .o files per YAML spec (delegates to Python)
#   build-wasm.sh full <config.yml>      All steps
#
# Environment variables:
#   OCJS_LTO      Enable LTO at link time (default: 1)
#   OCJS_OPT      Optimization level for compilation (default: -O2)
#   OCJS_JOBS     Parallel compilation jobs (default: nproc)
#   THREADING     single-threaded or multi-threaded (default: single-threaded)
set -euo pipefail

export OCJS_LTO="${OCJS_LTO:-1}"
export OCJS_OPT="${OCJS_OPT:--O2}"
export OCJS_JOBS="${OCJS_JOBS:-$(nproc)}"
export THREADING="${THREADING:-${threading:-single-threaded}}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── PCH subcommand ────────────────────────────────────────────────────
cmd_pch() {
  echo "=== Building flat includes + PCH ==="
  cd "${SCRIPT_DIR}" && python3 -c "from Common import buildFlatIncludes, buildPch; buildFlatIncludes(); buildPch('${THREADING}')"
}

# ── Compile subcommand ────────────────────────────────────────────────
cmd_compile() {
  echo "=== Compiling OCCT sources + bindings ==="

  # Delegate to existing Python scripts which handle:
  # - Package/module filtering (filterPackages.py)
  # - Source file filtering (filterSourceFiles.py)
  # - Parallel compilation via multiprocessing.Pool
  # - Graceful failure handling for problematic files
  "${SCRIPT_DIR}/compileBindings.py" "${THREADING}"
  "${SCRIPT_DIR}/compileSources.py" "${THREADING}"

  echo "=== Compilation complete ==="
}

# ── Link subcommand ───────────────────────────────────────────────────
cmd_link() {
  local config="${1:?Usage: build-wasm.sh link <config.yml>}"
  echo "=== Linking: ${config} ==="

  # Delegate to Python link helper (buildFromYaml.py) which handles:
  # - YAML parsing + validation
  # - On-demand binding compilation for missing .o files
  # - CONSTRUCTOR macro patching
  # - TypeScript .d.ts generation (170 lines of TS type assembly)
  # - Link command assembly (.o collection + emcc invocation)
  "${SCRIPT_DIR}/buildFromYaml.py" "${config}"

  # Post-link: wasm-opt optimization
  local name
  name="$(python3 -c "import yaml; print(yaml.safe_load(open('${config}'))['mainBuild']['name'])")"
  local wasm="${name%.js}.wasm"

  if [ -f "${wasm}" ]; then
    echo "  Running wasm-opt on ${wasm}..."
    wasm-opt -O3 --strip-debug --strip-producers "${wasm}" -o "${wasm}" 2>/dev/null || true
    echo "  Optimized: $(du -h "${wasm}" | cut -f1)"
  fi

  echo "=== Link complete ==="
}

# ── Full subcommand ───────────────────────────────────────────────────
cmd_full() {
  local config="${1:?Usage: build-wasm.sh full <config.yml>}"
  cmd_pch
  cmd_compile
  cmd_link "${config}"
}

# ── Main dispatch ─────────────────────────────────────────────────────
case "${1:-}" in
  pch)     cmd_pch ;;
  compile) cmd_compile ;;
  link)    shift; cmd_link "$@" ;;
  full)    shift; cmd_full "$@" ;;
  *)
    echo "Usage: build-wasm.sh {pch|compile|link|full} [args...]"
    echo ""
    echo "Subcommands:"
    echo "  pch              Generate precompiled header"
    echo "  compile          Compile OCCT sources + bindings"
    echo "  link <yml>       Link per YAML config"
    echo "  full <yml>       All steps (pch + compile + link)"
    echo ""
    echo "Environment:"
    echo "  OCJS_LTO=1       Enable LTO at link time"
    echo "  OCJS_OPT=-O2     Optimization level"
    echo "  OCJS_JOBS=$(nproc)     Parallel jobs"
    echo "  THREADING=single-threaded"
    exit 1
    ;;
esac
