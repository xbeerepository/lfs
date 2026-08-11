#!/usr/bin/env bash
set -euo pipefail
make -C src -j"$JOBS"
make -C src DESTDIR="$STAGE" PREFIX=/usr install
test -x "$STAGE/usr/bin/wg"
