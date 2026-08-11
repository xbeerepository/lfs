#!/usr/bin/env bash
set -euo pipefail

cmake -S . -B build \
  -D CMAKE_INSTALL_PREFIX=/usr \
  -D CMAKE_BUILD_TYPE=Release \
  -G Ninja
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
