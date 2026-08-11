#!/usr/bin/env bash
set -euo pipefail
meson setup build --prefix=/usr --buildtype=release -Dlibproxy=disabled
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
test -e "$STAGE/usr/lib/gio/modules/libgiognutls.so"
