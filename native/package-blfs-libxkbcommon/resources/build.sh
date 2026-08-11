#!/usr/bin/env bash
set -euo pipefail

meson setup build \
  --prefix=/usr \
  --buildtype=release \
  --wrap-mode=nofallback \
  -D enable-x11=false \
  -D enable-wayland=true \
  -D enable-xkbregistry=true \
  -D enable-docs=false
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
