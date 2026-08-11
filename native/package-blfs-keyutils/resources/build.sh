#!/usr/bin/env bash
set -euo pipefail
make -j"$JOBS"
make DESTDIR="$STAGE" NO_ARLIB=1 LIBDIR=/usr/lib BINDIR=/usr/bin SBINDIR=/usr/sbin install
test -x "$STAGE/usr/bin/keyctl"
