#!/usr/bin/env bash
set -euo pipefail
sed -i '/get_option/s/libdvdread/&-7.0.1/' meson.build
meson setup build --prefix=/usr --buildtype=release
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
rm -f "$STAGE/usr/lib/libdvdread.a"
test -e "$STAGE/usr/lib/libdvdread.so"
