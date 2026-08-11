#!/usr/bin/env bash
set -euo pipefail
./configure --prefix=/usr --with-cups-rundir=/run/cups --without-rcdir --disable-static --docdir=/usr/share/doc/cups-browsed-2.1.1
make -j"$JOBS"
make DESTDIR="$STAGE" install
test -x "$STAGE/usr/sbin/cups-browsed"
