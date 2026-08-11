#!/usr/bin/env bash
set -euo pipefail

gdk-pixbuf-query-loaders --update-cache

sed -i \
  "s|^subdir('demos/gtk-demo')$|if build_demos\\n  subdir('demos/gtk-demo')\\nendif|" \
  meson.build

meson setup build --prefix=/usr --buildtype=release --wrap-mode=nofallback \
  -Dbuild-documentation=false \
  -Dbuild-demos=false \
  -Dbuild-tests=false
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
