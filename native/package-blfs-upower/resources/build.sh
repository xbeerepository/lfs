#!/usr/bin/env bash
set -euo pipefail
meson setup build --prefix=/usr --buildtype=release -Dgtk-doc=false -Dman=false -Dintrospection=disabled
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
test -x "$STAGE/usr/bin/upower"
