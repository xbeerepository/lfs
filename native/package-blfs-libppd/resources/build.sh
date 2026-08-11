#!/usr/bin/env bash
set -euo pipefail
./configure --prefix=/usr --disable-static --disable-mutool --with-cups-rundir=/run/cups --disable-ppdc-utils --docdir=/usr/share/doc/libppd-2.1.1
make -j"$JOBS"
make DESTDIR="$STAGE" install
test -e "$STAGE/usr/lib/libppd.so"
