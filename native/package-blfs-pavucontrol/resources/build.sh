#!/usr/bin/env bash
set -euo pipefail

meson setup build --prefix=/usr --buildtype=release --wrap-mode=nofallback \
  -Dlynx=disabled
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
if [[ -d "$STAGE/usr/share/doc/pavucontrol" ]]; then
  mv "$STAGE/usr/share/doc/pavucontrol" \
    "$STAGE/usr/share/doc/pavucontrol-6.2"
fi
