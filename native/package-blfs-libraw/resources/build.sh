#!/usr/bin/env bash
set -euo pipefail
./configure --prefix=/usr --enable-jpeg --enable-jasper --enable-lcms --disable-static --docdir=/usr/share/doc/libraw-0.22.0
make -j"$JOBS"
make DESTDIR="$STAGE" install
test -e "$STAGE/usr/lib/libraw_r.so"
