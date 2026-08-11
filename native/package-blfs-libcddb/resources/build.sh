#!/usr/bin/env bash
set -euo pipefail
sed -e '/DEFAULT_SERVER/s/freedb.org/gnudb.gnudb.org/' -e '/DEFAULT_PORT/s/888/&0/' \
  -i include/cddb/cddb_ni.h
sed '/^Genre:/s/Trip-Hop/Electronic/' -i tests/testdata/920ef00b.txt
sed '/DISCID/i# Revision: 42' -i tests/testcache/misc/12340000
sed -i 's/size_t l;/socklen_t l;/' lib/cddb_net.c
./configure --prefix=/usr --disable-static
make -j"$JOBS"
make DESTDIR="$STAGE" install
test -x "$STAGE/usr/bin/cddb_query"
