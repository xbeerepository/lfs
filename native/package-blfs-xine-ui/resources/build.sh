#!/usr/bin/env bash
set -euo pipefail
./configure --prefix=/usr --without-x
make -j"$JOBS" CC="gcc -std=gnu17"
make DESTDIR="$STAGE" docsdir=/usr/share/doc/xine-ui-0.99.14 install
test -x "$STAGE/usr/bin/fbxine"
