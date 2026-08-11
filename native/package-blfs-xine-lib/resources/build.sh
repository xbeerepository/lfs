#!/usr/bin/env bash
set -euo pipefail
patch -Np1 -i /sources/xine-lib-1.2.13-upstream_fixes-1.patch
patch -Np1 -i /sources/xine-lib-1.2.13-gcc15_fixes-1.patch
patch -Np1 -i /sources/xine-lib-1.2.13-ffmpeg8.patch
./configure --prefix=/usr --disable-vcd --disable-w32dll --disable-vaapi --with-external-dvdnav --docdir=/usr/share/doc/xine-lib-1.2.13
make -j"$JOBS"
make DESTDIR="$STAGE" install
test -x "$STAGE/usr/bin/xine-config"
