#!/usr/bin/env bash
set -euo pipefail
./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var --disable-static --without-libidn2
make -j"$JOBS"
make DESTDIR="$STAGE" install
test -x "$STAGE/usr/bin/dig"
