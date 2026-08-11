#!/usr/bin/env bash
set -euo pipefail
cmake -S . -B build -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release -DBUILD_STATIC_LIBS=OFF -DBUILD_CODEC=ON
cmake --build build -j"$JOBS"
DESTDIR="$STAGE" cmake --install build
test -e "$STAGE/usr/lib/libopenjp2.so"
