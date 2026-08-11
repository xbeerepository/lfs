#!/usr/bin/env bash
set -euo pipefail

./configure \
  --prefix=/usr \
  --disable-static \
  --docdir=/usr/share/doc/libogg-1.3.6
make -j"$JOBS"
make check
make DESTDIR="$STAGE" install
