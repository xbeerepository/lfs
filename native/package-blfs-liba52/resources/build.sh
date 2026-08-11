#!/usr/bin/env bash
set -euo pipefail
CFLAGS="${CFLAGS:--g -O3} -fPIC" ./configure --prefix=/usr --mandir=/usr/share/man \
  --enable-shared --disable-static
make -j"$JOBS"
make check
make DESTDIR="$STAGE" install
cp liba52/a52_internal.h "$STAGE/usr/include/a52dec/"
install -Dm644 doc/liba52.txt "$STAGE/usr/share/doc/liba52-0.8.0/liba52.txt"
