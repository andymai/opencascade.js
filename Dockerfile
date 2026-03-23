FROM emscripten/emsdk:3.1.61 AS base-image

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

RUN \
  pip install \
  libclang==18.1.1 \
  pyyaml==6.0.2 \
  cerberus==1.3.4 \
  argparse==1.4.0

WORKDIR /rapidjson/
RUN \
  git clone --depth 1 -b master https://github.com/Tencent/rapidjson.git .

WORKDIR /freetype/
RUN \
  git clone -b VER-2-13-0 https://github.com/freetype/freetype.git .

ENV OCCT_COMMIT_HASH_FULL bb368e271e24f63078129283148ce83db6b9670a
WORKDIR /occt/
RUN \
  git clone --depth 1 https://github.com/Open-Cascade-SAS/OCCT.git /tmp/occt-repo && \
  cd /tmp/occt-repo && \
  git fetch --depth 1 origin ${OCCT_COMMIT_HASH_FULL} && \
  git checkout ${OCCT_COMMIT_HASH_FULL} && \
  cp -a /tmp/occt-repo/. /occt/ && \
  rm -rf /tmp/occt-repo

WORKDIR /opencascade.js/
COPY src ./src
WORKDIR /src/

ARG threading=single-threaded
ENV threading=$threading

FROM base-image AS test-image

RUN \
  mkdir /opencascade.js/build/ && \
  mkdir /opencascade.js/dist/ && \
  /opencascade.js/src/applyPatches.py

ENTRYPOINT ["/opencascade.js/src/buildFromYaml.py"]

FROM test-image AS custom-build-image

RUN \
  /opencascade.js/src/generateBindings.py && \
  /opencascade.js/src/compileBindings.py ${threading} && \
  /opencascade.js/src/compileSources.py ${threading} && \
  chmod -R 777 /opencascade.js/ && \
  chmod -R 777 /occt

ENTRYPOINT ["/opencascade.js/src/buildFromYaml.py"]
