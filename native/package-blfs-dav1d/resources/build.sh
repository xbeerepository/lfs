#!/usr/bin/env bash
set -euo pipefail

meson setup \
  --prefix=/usr \
  --buildtype=release \
  build
ninja -C build -j"$JOBS"
ninja -C build test
DESTDIR="$STAGE" ninja -C build install
