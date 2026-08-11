#!/usr/bin/env bash
set -euo pipefail

./configure \
  --prefix=/usr \
  --disable-docker-tests \
  --disable-static
make -j"$JOBS"
make DESTDIR="$STAGE" install
