#!/usr/bin/env bash
set -euo pipefail

meson setup build --prefix=/usr --buildtype=release --wrap-mode=nofallback
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
gtk-update-icon-cache -qtf "$STAGE/usr/share/icons/Adwaita"
