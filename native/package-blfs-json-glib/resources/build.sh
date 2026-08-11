#!/usr/bin/env bash
set -euo pipefail

meson setup build --prefix=/usr --buildtype=release --wrap-mode=nofallback \
  -Ddocumentation=disabled -Dman=false -Dtests=false -Dintrospection=enabled
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
test -e "$STAGE/usr/share/gir-1.0/Json-1.0.gir"
