#!/usr/bin/env bash
set -euo pipefail
cmake -S . -B build -D CMAKE_INSTALL_PREFIX=/usr -D CMAKE_BUILD_TYPE=Release \
  -D MOD_QT6=OFF -D MOD_SOX=OFF -D MOD_MOVIT=OFF -D MOD_VIDSTAB=OFF \
  -D MOD_JACKRACK=OFF -D MOD_RUBBERBAND=OFF -W no-dev
cmake --build build -j"$JOBS"
DESTDIR="$STAGE" cmake --install build
test -x "$STAGE/usr/bin/melt-7"
