#!/usr/bin/env bash
set -euo pipefail

./configure \
  --prefix=/usr \
  --disable-static \
  --enable-lib-only \
  --docdir="/usr/share/doc/nghttp2-$PACKAGE_VERSION"
make -j"$JOBS"
make DESTDIR="$STAGE" install
