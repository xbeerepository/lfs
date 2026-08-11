#!/usr/bin/env bash
set -euo pipefail
./configure --prefix=/usr --without-zenmap --without-nmap-update
make -j"$JOBS"
make DESTDIR="$STAGE" install
test -x "$STAGE/usr/bin/nmap"
