#!/usr/bin/env bash
set -euo pipefail
meson setup build --prefix=/usr --buildtype=release -Dx11=disabled -Dwayland=enabled -Ddvdnav=enabled
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
test -x "$STAGE/usr/bin/mpv"
