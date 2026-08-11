#!/usr/bin/env bash
set -euo pipefail
./configure --prefix=/usr --disable-static
make -j"$JOBS"
make check
make DESTDIR="$STAGE" install
test -e "$STAGE/usr/lib/libass.so"
