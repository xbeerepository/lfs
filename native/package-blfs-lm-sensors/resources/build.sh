#!/usr/bin/env bash
set -euo pipefail
make PREFIX=/usr BUILD_STATIC_LIB=0 MANDIR=/usr/share/man -j"$JOBS"
make PREFIX="$STAGE/usr" ETCDIR="$STAGE/etc" BUILD_STATIC_LIB=0 MANDIR="$STAGE/usr/share/man" install
install -d "$STAGE/usr/share/doc/lm-sensors-3-6-2"
cp -a README INSTALL doc/. "$STAGE/usr/share/doc/lm-sensors-3-6-2/"
test -x "$STAGE/usr/bin/sensors"
