#!/usr/bin/env bash
set -euo pipefail
./configure --prefix=/usr --sysconfdir=/etc --disable-static --with-kmod=no
make -j"$JOBS"
make DESTDIR="$STAGE" install
