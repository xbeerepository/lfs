#!/usr/bin/env bash
set -euo pipefail

meson setup build \
  --prefix=/usr \
  --buildtype=release \
  --wrap-mode=nodownload \
  -D gpl=enabled
ninja -C build -j"$JOBS"
ninja -C build test
find build -type f -name 'libgstasf.so' -print -quit | grep -q .
DESTDIR="$STAGE" ninja -C build install
