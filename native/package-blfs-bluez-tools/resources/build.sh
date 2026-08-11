#!/usr/bin/env bash
set -euo pipefail
./autogen.sh
./configure --prefix=/usr
make -j"$JOBS"
make DESTDIR="$STAGE" install
test -x "$STAGE/usr/bin/bt-adapter"
