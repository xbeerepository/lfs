#!/usr/bin/env bash
set -euo pipefail
./configure --prefix=/usr --disable-static
make -j"$JOBS"
make DESTDIR="$STAGE" docdir=/usr/share/doc/libatasmart-0.19 install
test -x "$STAGE/usr/sbin/skdump"
