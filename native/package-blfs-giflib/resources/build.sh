#!/usr/bin/env bash
set -euo pipefail

patch -Np1 -i "/sources/giflib-5.2.2-upstream_fixes-1.patch"
patch -Np1 -i "/sources/giflib-5.2.2-security_fixes-1.patch"
cp pic/gifgrid.gif doc/giflib-logo.gif
make -j"$JOBS"
make PREFIX=/usr DESTDIR="$STAGE" install
rm -f "$STAGE/usr/lib/libgif.a"
