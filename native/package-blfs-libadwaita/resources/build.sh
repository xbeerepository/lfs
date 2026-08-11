#!/usr/bin/env bash
set -euo pipefail
meson setup build --prefix=/usr --buildtype=release -Ddocumentation=false -Dtests=false -Dexamples=false -Dintrospection=enabled
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
test -e "$STAGE/usr/lib/libadwaita-1.so"
test -e "$STAGE/usr/share/vala/vapi/libadwaita-1.vapi"
