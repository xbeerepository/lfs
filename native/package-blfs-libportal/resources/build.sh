#!/usr/bin/env bash
set -euo pipefail
patch -Np1 -i /sources/libportal-0.9.1-qt6.9_fixes-1.patch
meson setup build --prefix=/usr --buildtype=release \
  -Dvapi=false -Ddocs=false -Dtests=false \
  -Dbackend-gtk3=enabled -Dbackend-gtk4=enabled \
  -Dbackend-qt5=disabled -Dbackend-qt6=disabled
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
test -e "$STAGE/usr/lib/libportal.so"
