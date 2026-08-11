#!/usr/bin/env bash
set -euo pipefail

meson setup build --prefix=/usr --buildtype=release --wrap-mode=nofallback \
  -Dbroadway-backend=false -Dx11-backend=false -Dwayland-backend=true \
  -Dintrospection=enabled -Dvulkan=disabled \
  -Dmedia-gstreamer=disabled \
  -Ddocumentation=false -Dman-pages=false \
  -Dbuild-tests=false -Dbuild-examples=false
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
test -f "$STAGE/usr/share/gir-1.0/Gtk-4.0.gir"
