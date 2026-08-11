#!/usr/bin/env bash
set -euo pipefail

./configure \
  --prefix=/usr \
  --disable-static \
  --disable-python
make -j"$JOBS"
make DESTDIR="$STAGE" install
