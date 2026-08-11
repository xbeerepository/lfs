#!/usr/bin/env bash
set -euo pipefail
./configure --prefix=/usr --disable-static --without-python
make -j"$JOBS"
make DESTDIR="$STAGE" install
test -e "$STAGE/usr/lib/libgsf-1.so"
