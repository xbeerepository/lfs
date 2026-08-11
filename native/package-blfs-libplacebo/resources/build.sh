#!/usr/bin/env bash
set -euo pipefail
meson setup build --prefix=/usr --buildtype=release -Dtests=true -Ddemos=false -Dvulkan=disabled
ninja -C build -j"$JOBS"
ninja -C build test
DESTDIR="$STAGE" ninja -C build install
