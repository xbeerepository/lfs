#!/usr/bin/env bash
set -euo pipefail
find . -type f -exec touch {} +
patch -Np1 -i /sources/libvpx-1.16.0-security_fix-1.patch
sed -i 's/cp -p/cp/' build/make/Makefile
mkdir libvpx-build
cd libvpx-build
../configure --prefix=/usr --enable-shared --disable-static
make -j"$JOBS"
make DESTDIR="$STAGE" install
test -x "$STAGE/usr/bin/vpxenc"
