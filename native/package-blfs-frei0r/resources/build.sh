#!/usr/bin/env bash
set -euo pipefail

cmake -S . -B build \
  -D CMAKE_INSTALL_PREFIX=/usr \
  -D CMAKE_BUILD_TYPE=Release \
  -W no-dev
cmake --build build -j"$JOBS"
find build -type f -name '*.so' -print -quit | grep -q .
DESTDIR="$STAGE" cmake --install build
