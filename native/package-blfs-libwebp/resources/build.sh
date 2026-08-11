#!/usr/bin/env bash
set -euo pipefail
./configure --prefix=/usr --disable-static --enable-libwebpmux --enable-libwebpdemux --enable-libwebpdecoder --enable-libwebpextras
make -j"$JOBS"
make DESTDIR="$STAGE" install
test -e "$STAGE/usr/lib/libwebp.so"
