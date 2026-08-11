#!/usr/bin/env bash
set -euo pipefail
meson setup build --prefix=/usr --buildtype=release
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
test -e "$STAGE/usr/lib/libbabl-0.1.so"
