#!/usr/bin/env bash
set -euo pipefail
meson setup build --prefix=/usr --buildtype=release
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
test -x "$STAGE/usr/bin/lsusb"
