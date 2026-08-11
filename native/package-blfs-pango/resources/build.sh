#!/usr/bin/env bash
set -euo pipefail

meson setup build \
  --prefix=/usr \
  --buildtype=release \
  --wrap-mode=nofallback \
  -D introspection=enabled \
  -D documentation=false \
  -D man-pages=false
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
test -f "$STAGE/usr/share/gir-1.0/Pango-1.0.gir"
