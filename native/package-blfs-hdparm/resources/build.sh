#!/usr/bin/env bash
set -euo pipefail
make -j"$JOBS"
make DESTDIR="$STAGE" binprefix=/usr install
test -x "$STAGE/usr/sbin/hdparm"
