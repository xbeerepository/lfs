#!/usr/bin/env bash
set -euo pipefail

tar -xf ../libsass-3.6.6.tar.gz
pushd libsass-3.6.6
autoreconf -fi
./configure --prefix=/usr --disable-static
make -j"$JOBS"
make install
make DESTDIR="$STAGE" install
popd

autoreconf -fi
./configure --prefix=/usr
make -j"$JOBS"
make DESTDIR="$STAGE" install

test -x "$STAGE/usr/bin/sassc"
test -e "$STAGE/usr/lib/libsass.so"
