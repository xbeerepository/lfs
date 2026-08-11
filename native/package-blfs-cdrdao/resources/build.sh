#!/usr/bin/env bash
set -euo pipefail
./configure --prefix=/usr --mandir=/usr/share/man
make -j"$JOBS" CC="gcc -std=gnu17"
make DESTDIR="$STAGE" install
test -x "$STAGE/usr/bin/cdrdao"
