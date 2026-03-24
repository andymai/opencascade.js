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
  git clone --depth 1 -b v1.1.0 https://github.com/Tencent/rapidjson.git .

WORKDIR /freetype/
RUN \
  git clone --depth 1 -b VER-2-13-0 https://github.com/freetype/freetype.git .

# OCCT V8.0.0 RC4 from GitHub tag
ENV OCCT_TAG=V8_0_0_rc4
WORKDIR /occt/
RUN \
  curl -fsSL "https://github.com/Open-Cascade-SAS/OCCT/archive/refs/tags/${OCCT_TAG}.tar.gz" \
    | tar xz --strip-components=1

ARG threading=single-threaded
ENV threading=${threading}

# ── Layer 1: patches + filter scripts (changes rarely) ───────────────
# Copy only patches and filter scripts first — these change infrequently.
# Changing build/link scripts won't invalidate binding generation cache.
WORKDIR /opencascade.js/
COPY src/patches ./src/patches
COPY src/filter ./src/filter
COPY src/emscripten_fix ./src/emscripten_fix
COPY src/undef_macros.h ./src/undef_macros.h

RUN \
  mkdir -p /opencascade.js/build/ && \
  mkdir -p /opencascade.js/dist/

# Apply patches
RUN \
  cd / && \
  for patch in /opencascade.js/src/patches/*.patch; do \
    echo "Applying patch: ${patch}" && \
    patch -p0 < "${patch}" || { echo "FAILED: ${patch}"; exit 1; }; \
  done

# ── Layer 2: binding generation (changes when filter scripts change) ──
COPY src/generateBindings.py src/bindings.py src/Common.py ./src/
COPY src/wasmGenerator ./src/wasmGenerator

RUN /opencascade.js/src/generateBindings.py

# ── Layer 3: compilation (changes when compile scripts change) ────────
COPY src/compileBindings.py src/compileSources.py ./src/

RUN \
  /opencascade.js/src/compileBindings.py ${threading} && \
  /opencascade.js/src/compileSources.py ${threading} && \
  chmod -R 777 /opencascade.js/ && \
  chmod -R 777 /occt

# ── Layer 4: link scripts (changes most frequently) ──────────────────
COPY src/buildFromYaml.py src/customBuildSchema.py ./src/
COPY src/build-wasm.sh src/build-native.sh src/setup-pch.sh src/listIncludes.py ./src/

WORKDIR /src/
ENTRYPOINT ["/opencascade.js/src/buildFromYaml.py"]
