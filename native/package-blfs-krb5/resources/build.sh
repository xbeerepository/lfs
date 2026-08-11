#!/usr/bin/env bash
set -euo pipefail
patch -Np1 -i /sources/mitkrb-1.22.2-upstream_fix-1.patch
cd src
sed -i -e '/eq 0/{N;s/12 //}' plugins/kdb/db2/libdb2/test/run.test
./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var/lib --runstatedir=/run --with-system-et --with-system-ss --disable-rpath
make -j"$JOBS"
make DESTDIR="$STAGE" install
test -x "$STAGE/usr/bin/kinit"
