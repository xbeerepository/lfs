#!/usr/bin/env bash
set -euo pipefail
./configure --prefix=/usr --disable-x11
make -j"$JOBS"
make DESTDIR="$STAGE" install
find "$STAGE/usr/lib" -name i965_drv_video.so -print -quit | grep -q .
