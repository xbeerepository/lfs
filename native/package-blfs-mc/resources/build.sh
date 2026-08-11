#!/usr/bin/env bash
set -euo pipefail
./configure --prefix=/usr --sysconfdir=/etc --enable-charset \
  --with-screen=ncurses
make -j"$JOBS"
make DESTDIR="$STAGE" install
test -x "$STAGE/usr/bin/mc"
