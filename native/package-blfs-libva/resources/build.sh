#!/usr/bin/env bash
set -euo pipefail
meson setup build --prefix=/usr --buildtype=release -Dwith_x11=no -Dwith_glx=no -Dwith_wayland=yes
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
test -e "$STAGE/usr/lib/libva.so"
test -e "$STAGE/usr/lib/libva-drm.so"
test -e "$STAGE/usr/lib/libva-wayland.so"
