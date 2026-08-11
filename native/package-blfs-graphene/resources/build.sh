#!/usr/bin/env bash
set -euo pipefail

meson setup build --prefix=/usr --buildtype=release --wrap-mode=nofallback \
  -Dintrospection=enabled -Dgtk_doc=false -Dtests=false
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
test -f "$STAGE/usr/share/gir-1.0/Graphene-1.0.gir"
