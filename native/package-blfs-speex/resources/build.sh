#!/usr/bin/env bash
set -euo pipefail
./configure --prefix=/usr --disable-static --docdir=/usr/share/doc/speex-1.2.1
make -j"$JOBS"
make DESTDIR="$STAGE" install
cd ..
tar -xf /sources/speexdsp-1.2.1.tar.gz
cd speexdsp-1.2.1
./configure --prefix=/usr --disable-static --docdir=/usr/share/doc/speexdsp-1.2.1
make -j"$JOBS"
make DESTDIR="$STAGE" install
test -e "$STAGE/usr/lib/libspeexdsp.so"
