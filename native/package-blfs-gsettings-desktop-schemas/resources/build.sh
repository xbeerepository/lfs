#!/usr/bin/env bash
set -euo pipefail

sed -i -r 's:"(/system):"/org/gnome\1:g' schemas/*.in
meson setup build --prefix=/usr --buildtype=release --wrap-mode=nofallback \
  -Dintrospection=false
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
glib-compile-schemas "$STAGE/usr/share/glib-2.0/schemas"
