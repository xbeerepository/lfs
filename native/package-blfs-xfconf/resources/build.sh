#!/usr/bin/env bash
set -euo pipefail
./configure --prefix=/usr --sysconfdir=/etc
make -j"$JOBS"
make DESTDIR="$STAGE" install
test -x "$STAGE/usr/bin/xfconf-query"
