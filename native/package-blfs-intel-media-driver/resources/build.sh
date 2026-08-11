#!/usr/bin/env bash
set -euo pipefail
cmake -S . -B build -D CMAKE_INSTALL_PREFIX=/usr -D CMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -D INSTALL_DRIVER_SYSCONF=OFF -D BUILD_TYPE=Release -D MEDIA_BUILD_FATAL_WARNINGS=OFF \
  -G Ninja -W no-dev
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
find "$STAGE/usr/lib" -name iHD_drv_video.so -print -quit | grep -q .
