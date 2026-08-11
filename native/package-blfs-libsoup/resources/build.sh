#!/usr/bin/env bash
set -euo pipefail
patch -Np1 -i /sources/libsoup-3.6.6-upstream_fixes-1.patch
meson setup build --prefix=/usr --buildtype=release -Ddocs=disabled -Dtests=false -Dvapi=disabled -Dsysprof=disabled
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
test -e "$STAGE/usr/lib/libsoup-3.0.so"
