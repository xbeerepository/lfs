#!/usr/bin/env bash
set -euo pipefail
./configure --sysconfdir=/etc
make -j"$JOBS"
make DESTDIR="$STAGE" install
test -x "$STAGE/usr/bin/rpcgen"
