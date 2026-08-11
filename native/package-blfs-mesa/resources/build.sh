#!/usr/bin/env bash
set -euo pipefail

meson setup build \
  --prefix=/usr \
  --buildtype=release \
  --wrap-mode=nofallback \
  -D platforms=wayland \
  -D egl=enabled \
  -D glx=disabled \
  -D gallium-drivers=softpipe \
  -D vulkan-drivers="" \
  -D valgrind=disabled \
  -D video-codecs="" \
  -D libunwind=disabled \
  -D build-tests=false
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
