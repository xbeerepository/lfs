#!/usr/bin/env bash
set -euo pipefail
./configure --prefix=/usr --sysconfdir=/etc --disable-static \
  --disable-cthelper --disable-cttimeout
make -j"$JOBS"
make DESTDIR="$STAGE" install
