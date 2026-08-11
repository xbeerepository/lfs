#!/usr/bin/env bash
set -euo pipefail
cmake -S . -B build -G Ninja -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release -DSDL_TEST_LIBRARY=OFF -DSDL_STATIC=OFF -DSDL_RPATH=OFF
cmake --build build -j"$JOBS"
DESTDIR="$STAGE" cmake --install build
test -e "$STAGE/usr/lib/libSDL3.so"
