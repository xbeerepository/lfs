#!/usr/bin/env bash
set -euo pipefail

sed -i '2i echo 26.27.3\nexit 0' generate-version.sh
meson setup build \
  --prefix=/usr \
  --buildtype=release \
  --wrap-mode=nofallback \
  -Dadmin_group=wheel \
  -Delogind=false \
  -Dsystemdsystemunitdir=/usr/lib/systemd/system \
  -Dintrospection=false \
  -Dvapi=false \
  -Ddocbook=false \
  -Dgtk_doc=false \
  -Dtests=false
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
