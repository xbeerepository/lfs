#!/usr/bin/env bash
set -euo pipefail
./configure --prefix=/usr
make -j"$JOBS"
make check
make DESTDIR="$STAGE" install
test -x "$STAGE/usr/bin/mpg123"
