#!/usr/bin/env bash
set -euo pipefail
patch -Np1 -i /sources/gpm-1.20.7-consolidated-1.patch
patch -Np1 -i /sources/gpm-1.20.7-gcc15_fixes-1.patch
./autogen.sh
./configure --prefix=/usr --sysconfdir=/etc ac_cv_path_emacs=no
make -j"$JOBS"
make DESTDIR="$STAGE" install
rm -f "$STAGE/usr/lib/libgpm.a"
ln -sf libgpm.so.2.1.0 "$STAGE/usr/lib/libgpm.so"
install -Dm644 conf/gpm-root.conf "$STAGE/etc/gpm-root.conf"
