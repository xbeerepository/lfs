#!/usr/bin/env bash
set -euo pipefail

meson setup build \
  --prefix=/usr \
  --buildtype=release \
  --wrap-mode=nofallback \
  -Dipc=disabled \
  -Dman-pages=disabled
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
