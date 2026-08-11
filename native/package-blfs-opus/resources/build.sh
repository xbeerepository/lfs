#!/usr/bin/env bash
set -euo pipefail
meson setup build --prefix=/usr --buildtype=release -Ddocdir=/usr/share/doc/opus-1.6.1
ninja -C build -j"$JOBS"
ninja -C build test
DESTDIR="$STAGE" ninja -C build install
test -e "$STAGE/usr/lib/libopus.so"
