#!/usr/bin/env bash
set -euo pipefail
cmake -S . -B build -G Ninja -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release -DCMAKE_SKIP_INSTALL_RPATH=ON -DSDL2COMPAT_STATIC=OFF -DSDL2COMPAT_TESTS=OFF -DSDL2COMPAT_X11=OFF
cmake --build build -j"$JOBS"
DESTDIR="$STAGE" cmake --install build
rm -f "$STAGE/usr/lib/libSDL2_test.a"
test -e "$STAGE/usr/lib/libSDL2.so"
