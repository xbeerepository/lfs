#!/usr/bin/env bash
set -euo pipefail

meson setup build \
  --prefix=/usr \
  --buildtype=release \
  --wrap-mode=nofallback \
  -D gdk-pixbuf=enabled \
  -D man-pages=disabled
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
