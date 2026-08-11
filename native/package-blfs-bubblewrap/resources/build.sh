#!/usr/bin/env bash
set -euo pipefail

meson setup build --prefix=/usr --buildtype=release --wrap-mode=nofallback \
  -Dtests=false
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
