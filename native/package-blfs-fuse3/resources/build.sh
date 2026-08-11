#!/usr/bin/env bash
set -euo pipefail

sed -i '/^udev/,$ s/^/#/' util/meson.build
meson setup build --prefix=/usr --buildtype=release --wrap-mode=nofallback \
  -Dexamples=false -Dtests=false
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
chmod u+s "$STAGE/usr/bin/fusermount3"
