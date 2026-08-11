#!/usr/bin/env bash
set -euo pipefail
sed -i '/typedef int bool;/d' src/encoder.h
cd build/generic
sed -i 's/^LN_S=@LN_S@/& -f -v/' platform.inc.in
./configure --prefix=/usr
make -j"$JOBS"
sed -i '/libdir.*STATIC_LIB/ s/^/#/' Makefile
make DESTDIR="$STAGE" install
chmod 755 "$STAGE/usr/lib/libxvidcore.so.4.3"
test -e "$STAGE/usr/lib/libxvidcore.so"
