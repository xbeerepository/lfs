#!/usr/bin/env bash
set -euo pipefail
unset ACLOCAL
./bootstrap
./configure --prefix=/usr --docdir=/usr/share/doc/soundtouch-2.4.0
make -j"$JOBS"
make DESTDIR="$STAGE" install
test -x "$STAGE/usr/bin/soundstretch"
