#!/usr/bin/env bash
set -euo pipefail
./configure --prefix=/usr --sysconfdir=/etc --disable-static \
  --disable-dco --disable-lzo
make -j"$JOBS"
make DESTDIR="$STAGE" install
