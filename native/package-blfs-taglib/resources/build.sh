#!/usr/bin/env bash
set -euo pipefail
cmake -S . -B build -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON
cmake --build build -j"$JOBS"
DESTDIR="$STAGE" cmake --install build
test -x "$STAGE/usr/bin/taglib-config"
