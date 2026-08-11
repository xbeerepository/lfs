#!/usr/bin/env bash
set -euo pipefail

patch -Np1 -i ../glib-2.86.4-upstream_fixes-1.patch

meson setup build \
  --prefix=/usr \
  --buildtype=release \
  -D introspection=enabled \
  -D glib_debug=disabled \
  -D man-pages=disabled \
  -D sysprof=disabled
ninja -C build -j"$JOBS"

full_stage="${STAGE}.full"
DESTDIR="$full_stage" ninja -C build install
mkdir -p "$STAGE/usr/share" "$STAGE/usr/lib"
cp -a "$full_stage/usr/share/gir-1.0" "$STAGE/usr/share/"
cp -a "$full_stage/usr/lib/girepository-1.0" "$STAGE/usr/lib/"
test -e "$STAGE/usr/share/gir-1.0/Gio-2.0.gir"
test -e "$STAGE/usr/lib/girepository-1.0/Gio-2.0.typelib"
