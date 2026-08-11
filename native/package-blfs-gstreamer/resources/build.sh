#!/usr/bin/env bash
set -euo pipefail

meson setup build --prefix=/usr --buildtype=release --wrap-mode=nofallback \
  -Dgst_debug=false
ninja -C build -j"$JOBS"
ninja -C build test
DESTDIR="$STAGE" ninja -C build install
