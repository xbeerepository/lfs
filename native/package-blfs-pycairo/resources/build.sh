#!/usr/bin/env bash
set -euo pipefail
meson setup build --prefix=/usr --buildtype=release
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
test -d "$STAGE/usr/lib/python3.14/site-packages/cairo"
