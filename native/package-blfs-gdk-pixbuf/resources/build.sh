#!/usr/bin/env bash
set -euo pipefail

meson setup build \
  --prefix=/usr \
  --buildtype=release \
  --wrap-mode=nofallback \
  -D png=enabled \
  -D gif=enabled \
  -D jpeg=enabled \
  -D tiff=enabled \
  -D thumbnailer=disabled \
  -D glycin=disabled \
  -D introspection=enabled \
  -D man=false \
  -D tests=false
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
test -f "$STAGE/usr/share/gir-1.0/GdkPixbuf-2.0.gir"

cache_dir="$STAGE/usr/lib/gdk-pixbuf-2.0/2.10.0"
install -d "$cache_dir"
GDK_PIXBUF_MODULEDIR="$cache_dir/loaders" \
LD_LIBRARY_PATH="$STAGE/usr/lib" \
  "$STAGE/usr/bin/gdk-pixbuf-query-loaders" >"$cache_dir/loaders.cache"
sed -i "s|$STAGE||g" "$cache_dir/loaders.cache"
LD_LIBRARY_PATH="$STAGE/usr/lib" \
  "$STAGE/usr/bin/gdk-pixbuf-pixdata" tests/test-image.png /dev/null
