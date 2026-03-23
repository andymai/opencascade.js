#!/usr/bin/env bash
# setup-pch.sh — Create a precompiled header for OCCT to speed up compilation.
#
# Creates a flat symlink directory of all OCCT headers, generates a master
# include file (pch.h), and compiles it to pch.h.pch. Subsequent compilations
# use -include-pch pch.h.pch instead of hundreds of -I flags per file.
set -euo pipefail

OCCT_SRC="${OCCT_SRC:-/occt/src}"
PCH_DIR="${PCH_DIR:-/opencascade.js/build/pch}"
PCH_INCLUDES="${PCH_DIR}/includes"
PCH_FILE="${PCH_DIR}/pch.h"
PCH_OUT="${PCH_DIR}/pch.h.pch"

THREADING="${THREADING:-single-threaded}"
OCJS_OPT="${OCJS_OPT:--O2}"

echo "=== Setting up PCH ==="

# Step 1: Create flat symlink directory of all .hxx headers
mkdir -p "${PCH_INCLUDES}"
find "${OCCT_SRC}" -name '*.hxx' -o -name '*.h' | while read -r hdr; do
  base="$(basename "${hdr}")"
  # Only create symlink if it doesn't already exist (first-wins for duplicates)
  if [ ! -e "${PCH_INCLUDES}/${base}" ]; then
    ln -s "${hdr}" "${PCH_INCLUDES}/${base}"
  fi
done

echo "  Symlinked $(find "${PCH_INCLUDES}" -type l | wc -l) headers"

# Step 2: Generate pch.h using Python helper (respects filter scripts)
python3 /opencascade.js/src/listIncludes.py > "${PCH_FILE}"
echo "  Generated $(wc -l < "${PCH_FILE}") includes in pch.h"

# Step 3: Collect all OCCT include directories for the PCH compilation
INCLUDE_ARGS=()
while IFS= read -r -d '' dir; do
  INCLUDE_ARGS+=("-I${dir}")
done < <(find "${OCCT_SRC}" -type d -print0)
INCLUDE_ARGS+=("-I/rapidjson/include" "-I/freetype/include/freetype" "-I/freetype/include")

# Step 4: Compile the PCH
THREAD_FLAG=""
if [ "${THREADING}" = "multi-threaded" ]; then
  THREAD_FLAG="-pthread"
fi

echo "  Compiling PCH..."
emcc -xc++-header "${PCH_FILE}" -o "${PCH_OUT}" \
  -fwasm-exceptions \
  -DIGNORE_NO_ATOMICS=1 \
  -DOCCT_NO_PLUGINS \
  -frtti \
  -DHAVE_RAPIDJSON \
  "${OCJS_OPT}" \
  ${THREAD_FLAG} \
  "${INCLUDE_ARGS[@]}"

echo "  PCH compiled: $(du -h "${PCH_OUT}" | cut -f1)"
echo "=== PCH setup complete ==="
