#!/usr/bin/env bash
set -euo pipefail

./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var \
  --disable-static
make -j"$JOBS"
make DESTDIR="$STAGE" install
