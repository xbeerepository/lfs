#!/usr/bin/env bash
set -euo pipefail
meson setup build --prefix=/usr --buildtype=release
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
rm -f "$STAGE/usr/lib/libdvdcss.a"
test -e "$STAGE/usr/lib/libdvdcss.so"
