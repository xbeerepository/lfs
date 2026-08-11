#!/usr/bin/env bash
set -euo pipefail

meson setup build \
  --prefix=/usr \
  --buildtype=release \
  --wrap-mode=nofallback \
  -Ddocs=disabled \
  -Dgrapheme-shaping=enabled \
  -Drun-shaping=disabled \
  -Dexamples=false
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
