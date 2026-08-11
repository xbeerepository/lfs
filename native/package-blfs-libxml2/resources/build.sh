#!/usr/bin/env bash
set -euo pipefail

sed -i "/'git'/,+3d" meson.build
mkdir build
cd build
meson setup .. \
  --prefix=/usr \
  --buildtype=release \
  -D history=enabled \
  -D icu=disabled \
  -D python=disabled
ninja -j"$JOBS"
DESTDIR="$STAGE" ninja install
sed 's/--static/--shared/' -i "$STAGE/usr/bin/xml2-config"
