#!/usr/bin/env bash
set -euo pipefail

meson setup build --prefix=/usr --buildtype=release --wrap-mode=nofallback \
  -Ddefault_library=shared -Ddistro_install=true
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
