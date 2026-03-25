FROM emscripten/emsdk:5.0.3 AS base-image

RUN \
  apt update -y && \
  apt install -y \
  bash \
  build-essential \
  cmake \
  curl \
  git \
  libffi-dev \
  libgdbm-dev \
  libncurses5-dev \
  libnss3-dev \
  libreadline-dev \
  libsqlite3-dev \
  libssl-dev \
  libbz2-dev \
  npm \
  python3 \
  python3-pip \
  python3-setuptools \
  zlib1g-dev

# libclang 18.1.1 is used only for header parsing (generateBindings.py),
# not for compilation. It does not need to match emsdk's LLVM 21.
RUN \
  pip install --break-system-packages \
  libclang==18.1.1 \
  pyyaml==6.0.2 \
  cerberus==1.3.4 \
  argparse==1.4.0

WORKDIR /rapidjson/
RUN \
  git clone --depth 1 -b master https://github.com/Tencent/rapidjson.git .

WORKDIR /freetype/
RUN \
  git clone --depth 1 -b VER-2-13-0 https://github.com/freetype/freetype.git .

# OCCT V8.0.0 RC4 from GitHub tag
ENV OCCT_TAG=V8_0_0_rc4
WORKDIR /occt/
RUN \
  curl -fsSL "https://github.com/Open-Cascade-SAS/OCCT/archive/refs/tags/${OCCT_TAG}.tar.gz" \
    | tar xz --strip-components=1

# Generate Standard_Version.hxx (normally created by CMake)
RUN \
  sed -e 's/@OCC_VERSION_MAJOR@/8/g' \
      -e 's/@OCC_VERSION_MINOR@/0/g' \
      -e 's/@OCC_VERSION_MAINTENANCE@/0/g' \
      -e 's/@SET_OCC_VERSION_DEVELOPMENT@/#define OCC_VERSION_DEVELOPMENT "rc4"/g' \
      -e 's/@OCCT_VERSION_DATE@/2026-02-16/g' \
      /occt/adm/templates/Standard_Version.hxx.in \
      > /occt/src/FoundationClasses/TKernel/Standard/Standard_Version.hxx

ARG threading=single-threaded
ENV threading=${threading}

# Compile-time optimization: -O2 + LTO (benchmarked 10% faster than -Os+LTO)
ENV OCJS_OPT="-O2"
ENV OCJS_LTO="1"

WORKDIR /opencascade.js/
RUN mkdir -p /opencascade.js/build/ /opencascade.js/dist/

# ── Layer 1: Patches (standalone, no src/ imports) ───────────────────
COPY src/applyPatches.py ./src/applyPatches.py
RUN python3 /opencascade.js/src/applyPatches.py

# ── Layer 2: Filters + Common (changes rarely after V8 stabilizes) ───
COPY src/filter ./src/filter
COPY src/Common.py src/TuInfo.py ./src/
COPY src/wasmGenerator ./src/wasmGenerator

# Build flat include directory (needed by all subsequent steps)
RUN cd /opencascade.js/src && python3 -c "from Common import buildFlatIncludes; buildFlatIncludes()"

# ── Layer 3: Binding generation (changes when generator logic changes)
RUN apt-get update -qq && apt-get install -y -qq doxygen > /dev/null 2>&1 && rm -rf /var/lib/apt/lists/*
COPY src/generateBindings.py src/bindings.py src/extract_docs.py ./src/

RUN /opencascade.js/src/generateBindings.py

# Build PCH (after bindings exist, before compilation)
RUN cd /opencascade.js/src && python3 -c "from Common import buildPch; buildPch('${threading}')"

# ── Layer 4: Compilation (changes when compile scripts change) ───────
COPY src/compileBindings.py src/compileSources.py ./src/

RUN \
  /opencascade.js/src/compileBindings.py ${threading} && \
  /opencascade.js/src/compileSources.py ${threading} && \
  chmod -R 777 /opencascade.js/ && \
  chmod -R 777 /occt

# ── Layer 5: Link scripts (changes most often, <1s rebuild) ─────────
COPY src/buildFromYaml.py src/customBuildSchema.py ./src/
COPY src/patches ./src/patches
COPY src/build-wasm.sh src/build-native.sh ./src/

WORKDIR /src/
ENTRYPOINT ["/opencascade.js/src/buildFromYaml.py"]
