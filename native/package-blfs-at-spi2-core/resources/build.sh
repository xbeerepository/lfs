#!/usr/bin/env bash
set -euo pipefail

meson setup build --prefix=/usr --buildtype=release --wrap-mode=nofallback \
  -Dx11=disabled -Dintrospection=enabled -Ddocs=false \
  -Dgtk2_atk_adaptor=false -Ddefault_bus=dbus-daemon
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
