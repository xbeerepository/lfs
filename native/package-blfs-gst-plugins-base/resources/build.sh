#!/usr/bin/env bash
set -euo pipefail

meson setup build --prefix=/usr --buildtype=release --wrap-mode=nodownload
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
test -f "$STAGE/usr/lib/pkgconfig/gstreamer-gl-1.0.pc"
