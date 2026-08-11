#!/usr/bin/env bash
set -euo pipefail
./configure --prefix=/usr --enable-vcut
make -j"$JOBS"
make DESTDIR="$STAGE" install
test -x "$STAGE/usr/bin/ogg123"
