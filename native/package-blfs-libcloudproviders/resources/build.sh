#!/usr/bin/env bash
set -euo pipefail
meson setup build --prefix=/usr --buildtype=release \
  -Denable-gtk-doc=false -Dvapigen=false
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
test -e "$STAGE/usr/lib/libcloudproviders.so"
