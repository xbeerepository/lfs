#!/usr/bin/env bash
set -euo pipefail
patch -Np1 -i /sources/libaom-3.13.1-nasm3-1.patch
sed -i 's/aom aom_static/aom/' build/cmake/aom_install.cmake
cmake -S . -B aom-build -D CMAKE_INSTALL_PREFIX=/usr -D CMAKE_BUILD_TYPE=Release \
  -D BUILD_SHARED_LIBS=1 -D ENABLE_DOCS=no -G Ninja
ninja -C aom-build -j"$JOBS"
DESTDIR="$STAGE" ninja -C aom-build install
test -x "$STAGE/usr/bin/aomenc"
test -e "$STAGE/usr/lib/libaom.so"
