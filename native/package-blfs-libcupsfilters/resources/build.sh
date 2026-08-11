#!/usr/bin/env bash
set -euo pipefail
patch -Np1 -i /sources/libcupsfilters-2.1.1-security_fixes-1.patch
./configure --prefix=/usr \
  --disable-static \
  --disable-mutool \
  --with-test-font-path=/usr/share/fonts/TTF/DejaVuSans.ttf \
  --docdir=/usr/share/doc/libcupsfilters-2.1.1
make -j"$JOBS"
make DESTDIR="$STAGE" install
test -e "$STAGE/usr/lib/libcupsfilters.so"
