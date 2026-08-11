#!/usr/bin/env bash
set -euo pipefail
make -j"$JOBS"
make DESTDIR="$STAGE" install
test -x "$STAGE/usr/bin/lsb_release"
