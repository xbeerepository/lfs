#!/usr/bin/env bash
set -euo pipefail
sed -i '/get_option/s/libdvdnav/&-7.0.0/' meson.build
meson setup build --prefix=/usr --buildtype=release
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
rm -f "$STAGE/usr/lib/libdvdnav.a"
test -e "$STAGE/usr/lib/libdvdnav.so"
