#!/usr/bin/env bash
set -euo pipefail

meson setup build \
  --prefix=/usr \
  --buildtype=release \
  --wrap-mode=nofallback \
  -D examples=false \
  -D xwayland=disabled \
  -D renderers=gles2 \
  -D backends=drm,libinput \
  -D allocators=gbm \
  -D session=enabled \
  -D color-management=disabled \
  -D libliftoff=enabled
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
