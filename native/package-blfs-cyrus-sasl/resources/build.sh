#!/usr/bin/env bash
set -euo pipefail
patch -Np1 -i /sources/cyrus-sasl-2.1.28-gcc15_fixes-1.patch
sed -i '/#include "saslint.h"/i #include <time.h>' lib/saslutil.c
for source in plugins/cram.c plugins/otp.c plugins/digestmd5.c \
              saslauthd/auth_shadow.c; do
  sed -i '1i #include <time.h>' "$source"
done
autoreconf -fi
./configure --prefix=/usr --sysconfdir=/etc --enable-auth-sasldb --with-dbpath=/var/lib/sasl/sasldb2 --with-saslauthd=/var/run/saslauthd
make -j"$JOBS"
make DESTDIR="$STAGE" install
install -d "$STAGE/var/lib/sasl" "$STAGE/etc/sasl2"
