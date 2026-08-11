#!/usr/bin/env bash
set -euo pipefail
./configure --prefix=/usr --disable-static
make -j"$JOBS"
make DESTDIR="$STAGE" install
test -x "$STAGE/usr/bin/sg_inq"
