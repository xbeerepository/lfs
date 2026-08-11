#!/usr/bin/env bash
set -euo pipefail
patch -Np1 -i /sources/openldap-2.6.12-consolidated-1.patch
./configure --prefix=/usr --sysconfdir=/etc --disable-static --enable-dynamic --disable-debug --disable-slapd
make depend
make -j"$JOBS"
make DESTDIR="$STAGE" install
test -x "$STAGE/usr/bin/ldapsearch"
