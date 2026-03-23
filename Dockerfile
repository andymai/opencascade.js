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
  pip install \
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

WORKDIR /opencascade.js/
COPY src ./src
WORKDIR /src/

ARG threading=single-threaded
ENV threading=${threading}

# ── base-image: deps + OCCT + patches ────────────────────────────────
FROM base-image AS patched-image

RUN \
  mkdir -p /opencascade.js/build/ && \
  mkdir -p /opencascade.js/dist/

# Apply patches (replaces applyPatches.py)
RUN \
  cd / && \
  for patch in /opencascade.js/src/patches/*.patch; do \
    echo "Applying patch: ${patch}" && \
    patch -p0 < "${patch}" || { echo "FAILED: ${patch}"; exit 1; }; \
  done

# ── bindings-image: generate C++ bindings from OCCT headers ──────────
FROM patched-image AS bindings-image

RUN /opencascade.js/src/generateBindings.py

# ── compiled-image: compile all sources + bindings to .o ─────────────
FROM bindings-image AS compiled-image

# Pre-build LTO sysroot before compilation
RUN embuilder build ALL --lto

RUN \
  /opencascade.js/src/compileBindings.py ${threading} && \
  /opencascade.js/src/compileSources.py ${threading} && \
  chmod -R 777 /opencascade.js/ && \
  chmod -R 777 /occt

ENTRYPOINT ["/opencascade.js/src/buildFromYaml.py"]
