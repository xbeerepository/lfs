#!/usr/bin/env bash
set -euo pipefail
./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var \
  --enable-fhs --with-pam --without-ad-dc --without-json \
  --without-ldb-lmdb \
  --bundled-libraries=cmocka,popt
make -j"$JOBS"
make DESTDIR="$STAGE" install
install -d "$STAGE/etc/samba"
test -x "$STAGE/usr/bin/smbclient"
