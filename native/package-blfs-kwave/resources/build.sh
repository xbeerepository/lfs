#!/usr/bin/env bash
set -euo pipefail
export PATH="/opt/qt6/bin:/opt/kf6/bin:$PATH"
export CMAKE_PREFIX_PATH="/opt/kf6;/opt/qt6"
export LD_LIBRARY_PATH="/opt/qt6/lib:/opt/kf6/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
cmake -S . -B build -DCMAKE_INSTALL_PREFIX=/opt/kf6 -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF -Wno-dev
cmake --build build -j"$JOBS"
DESTDIR="$STAGE" cmake --install build
test -x "$STAGE/opt/kf6/bin/kwave"
