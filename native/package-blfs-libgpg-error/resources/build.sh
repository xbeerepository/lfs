#!/usr/bin/env bash
set -euo pipefail
./configure --prefix=/usr --sysconfdir=/etc
make -j"$JOBS"
make check
make DESTDIR="$STAGE" install
test -e "$STAGE/usr/lib/libgpg-error.so"
