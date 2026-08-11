#!/usr/bin/env bash
set -euo pipefail
meson setup build --prefix=/usr --buildtype=release -Dgconv=disabled -Ddoxygen-doc=disabled
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
test -x "$STAGE/usr/bin/v4l2-ctl"
