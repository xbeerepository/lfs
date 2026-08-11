#!/usr/bin/env bash
set -euo pipefail

cmake -S . -B build -G Ninja \
  -DCMAKE_INSTALL_PREFIX=/usr \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=ON \
  -DFMT_DOC=OFF \
  -DFMT_TEST=OFF
cmake --build build -j"$JOBS"
DESTDIR="$STAGE" cmake --install build
