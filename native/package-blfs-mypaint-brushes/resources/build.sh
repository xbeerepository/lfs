#!/usr/bin/env bash
set -euo pipefail
./configure --prefix=/usr
make -j"$JOBS"
make DESTDIR="$STAGE" install
test -d "$STAGE/usr/share/mypaint-data/1.0/brushes"
