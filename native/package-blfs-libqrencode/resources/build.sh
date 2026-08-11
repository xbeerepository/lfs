#!/usr/bin/env bash
set -euo pipefail
sh autogen.sh
./configure --prefix=/usr
make -j"$JOBS"
make DESTDIR="$STAGE" install
test -x "$STAGE/usr/bin/qrencode"
