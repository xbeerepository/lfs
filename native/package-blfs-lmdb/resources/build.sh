#!/usr/bin/env bash
set -euo pipefail
cd libraries/liblmdb
make -j"$JOBS"
sed -i 's| liblmdb.a||' Makefile
make DESTDIR="$STAGE" prefix=/usr install
test -x "$STAGE/usr/bin/mdb_stat"
