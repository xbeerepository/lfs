#!/usr/bin/env bash
set -euo pipefail
meson setup build --prefix=/usr --buildtype=release \
  -Ddocs=false -Dintrospection=true -Dvapi=true
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
test -e "$STAGE/usr/lib/libgusb.so"
test -e "$STAGE/usr/share/vala/vapi/gusb.vapi"
