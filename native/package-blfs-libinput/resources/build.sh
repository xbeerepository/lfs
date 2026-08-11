#!/usr/bin/env bash
set -euo pipefail

meson setup build \
  --prefix=/usr \
  --buildtype=release \
  --wrap-mode=nofallback \
  -D debug-gui=false \
  -D tests=false \
  -D libwacom=false \
  -D documentation=false \
  -D udev-dir=/usr/lib/udev
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
