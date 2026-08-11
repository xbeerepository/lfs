#!/usr/bin/env bash
set -euo pipefail
sed -i '/install.*libaio.a/s/^/#/' src/Makefile
make -j"$JOBS"
make DESTDIR="$STAGE" install
test -e "$STAGE/usr/lib/libaio.so"
