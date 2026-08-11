#!/usr/bin/env bash
set -euo pipefail

meson setup build --prefix=/usr --buildtype=release --wrap-mode=nofallback \
  -Ddaemon=false \
  -Dclient=true \
  -Ddoxygen=false \
  -Dman=false \
  -Dtests=false \
  -Dglib=enabled \
  -Ddbus=disabled \
  -Dopenssl=disabled \
  -Dsystemd=disabled \
  -Dx11=disabled
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
