#!/usr/bin/env bash
set -euo pipefail
./configure --prefix=/usr --disable-valadoc
make -j"$JOBS"
make DESTDIR="$STAGE" install
test -x "$STAGE/usr/bin/valac"
