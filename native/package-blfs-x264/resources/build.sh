#!/usr/bin/env bash
set -euo pipefail
./configure --prefix=/usr --enable-shared --disable-cli
make -j"$JOBS"
make DESTDIR="$STAGE" install
test -e "$STAGE/usr/lib/libx264.so"
