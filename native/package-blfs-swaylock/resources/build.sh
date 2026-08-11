#!/usr/bin/env bash
set -euo pipefail

meson setup build \
  --prefix=/usr \
  --sysconfdir=/etc \
  --buildtype=release \
  --wrap-mode=nofallback \
  -Dpam=enabled \
  -Dgdk-pixbuf=enabled \
  -Dman-pages=disabled
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
