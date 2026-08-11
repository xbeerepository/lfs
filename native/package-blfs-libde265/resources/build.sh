#!/usr/bin/env bash
set -euo pipefail
sed '/tools/d' -i Makefile.am
./autogen.sh
./configure --prefix=/usr --disable-sherlock265 --disable-static
make -j"$JOBS"
make DESTDIR="$STAGE" install
test -x "$STAGE/usr/bin/dec265"
test -e "$STAGE/usr/lib/libde265.so"
