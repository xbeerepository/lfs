#!/usr/bin/env bash
set -euo pipefail

meson setup build \
  --prefix=/usr \
  --buildtype=release \
  -D graphite2=enabled \
  -D docs=disabled \
  -D tests=disabled
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
test -f "$STAGE/usr/share/gir-1.0/HarfBuzz-0.0.gir"
