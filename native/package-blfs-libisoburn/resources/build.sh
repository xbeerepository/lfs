#!/usr/bin/env bash
set -euo pipefail
./configure --prefix=/usr --disable-static --enable-pkg-check-modules
make -j"$JOBS"
make DESTDIR="$STAGE" install
test -x "$STAGE/usr/bin/xorriso"
