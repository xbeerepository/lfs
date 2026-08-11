#!/usr/bin/env bash
set -euo pipefail

cmake -S . -B build -G Ninja \
  -DCMAKE_INSTALL_PREFIX=/usr \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=ON \
  -DSPDLOG_BUILD_EXAMPLE=OFF \
  -DSPDLOG_BUILD_TESTS=OFF \
  -DSPDLOG_BUILD_BENCH=OFF \
  -DSPDLOG_FMT_EXTERNAL=ON
cmake --build build -j"$JOBS"
DESTDIR="$STAGE" cmake --install build
