#!/usr/bin/env bash
set -euo pipefail
./configure --prefix=/usr --disable-static
make -j"$JOBS"
make DESTDIR="$STAGE" install

tar -xf /sources/libcdio-paranoia-10.2+2.0.2.tar.bz2
cd libcdio-paranoia-10.2+2.0.2
PKG_CONFIG_PATH="$STAGE/usr/lib/pkgconfig" \
  PKG_CONFIG_SYSROOT_DIR="$STAGE" \
  ./configure --prefix=/usr --disable-static
make -j"$JOBS"
LD_LIBRARY_PATH="$STAGE/usr/lib" make check
make DESTDIR="$STAGE" install
test -x "$STAGE/usr/bin/cd-paranoia"
