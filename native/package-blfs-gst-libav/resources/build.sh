#!/usr/bin/env bash
set -euo pipefail

meson setup build \
  --prefix=/usr \
  --buildtype=release \
  --wrap-mode=nodownload
ninja -C build -j"$JOBS"
ninja -C build test
test -f build/ext/libav/libgstlibav.so
DESTDIR="$STAGE" ninja -C build install
