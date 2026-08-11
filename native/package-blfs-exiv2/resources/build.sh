#!/usr/bin/env bash
set -euo pipefail
cmake -S . -B build -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release -DEXIV2_BUILD_SAMPLES=OFF -DEXIV2_BUILD_UNIT_TESTS=OFF -DEXIV2_ENABLE_BMFF=ON
cmake --build build -j"$JOBS"
DESTDIR="$STAGE" cmake --install build
test -x "$STAGE/usr/bin/exiv2"
