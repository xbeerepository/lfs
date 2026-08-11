#!/usr/bin/env bash
set -euo pipefail

meson setup build \
  --prefix=/usr \
  --buildtype=release \
  --wrap-mode=nodownload \
  -D gpl=enabled
ninja -C build -j"$JOBS"
find build -type f -name 'libgstvideoparsersbad.so' -print -quit | grep -q .
DESTDIR="$STAGE" ninja -C build install
