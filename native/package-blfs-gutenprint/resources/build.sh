#!/usr/bin/env bash
set -euo pipefail
sed -i 's/^doc_DATA =/#&/' Makefile.in
./configure --prefix=/usr --disable-static --without-gimp2 --without-gimp2-as-gutenprint
make -j"$JOBS"
make DESTDIR="$STAGE" install
test -x "$STAGE/usr/sbin/cups-genppdupdate"
