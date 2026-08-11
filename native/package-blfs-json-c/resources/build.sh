#!/usr/bin/env bash
set -euo pipefail

sed -i 's/VERSION 2.8/VERSION 4.0/' apps/CMakeLists.txt
sed -i 's/VERSION 3.9/VERSION 4.0/' tests/CMakeLists.txt

cmake -S . -B build \
  -D CMAKE_INSTALL_PREFIX=/usr \
  -D CMAKE_BUILD_TYPE=Release \
  -D BUILD_STATIC_LIBS=OFF \
  -D BUILD_TESTING=OFF
cmake --build build -j"$JOBS"
DESTDIR="$STAGE" cmake --install build
