#!/usr/bin/env bash
set -euo pipefail
./configure --prefix=/usr --disable-static
make -j"$JOBS"
make DESTDIR="$STAGE" docdir=/usr/share/doc/libdaemon-0.14 install
test -e "$STAGE/usr/lib/libdaemon.so"
