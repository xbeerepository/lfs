#!/usr/bin/env bash
set -euo pipefail
./configure --prefix=/usr --disable-xv --disable-static
make -j"$JOBS"
make DESTDIR="$STAGE" install
install -d "$STAGE/usr/share/doc/libdv-1.0.0"
install -m644 README* "$STAGE/usr/share/doc/libdv-1.0.0/"
test -e "$STAGE/usr/lib/libdv.so"
