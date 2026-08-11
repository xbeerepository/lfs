#!/usr/bin/env bash
set -euo pipefail

patch -Np1 -i ../glib-2.86.4-upstream_fixes-1.patch

meson setup build \
  --prefix=/usr \
  --buildtype=release \
  -D introspection=disabled \
  -D glib_debug=disabled \
  -D man-pages=disabled \
  -D sysprof=disabled
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
