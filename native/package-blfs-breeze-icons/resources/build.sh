#!/usr/bin/env bash
set -euo pipefail
export PATH="/opt/qt6/bin:$PATH"
export LD_LIBRARY_PATH="/opt/qt6/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
cmake -S . -B build -DCMAKE_INSTALL_PREFIX=/usr -DBUILD_TESTING=OFF -DWITH_ICON_GENERATION=OFF -Wno-dev
cmake --build build -j"$JOBS"
DESTDIR="$STAGE" cmake --install build
test -d "$STAGE/usr/share/icons/breeze"
