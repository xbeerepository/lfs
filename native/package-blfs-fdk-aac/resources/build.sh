#!/usr/bin/env bash
set -euo pipefail

./configure \
  --prefix=/usr \
  --disable-static
make -j"$JOBS"

test -f .libs/libfdk-aac.so

make DESTDIR="$STAGE" install
