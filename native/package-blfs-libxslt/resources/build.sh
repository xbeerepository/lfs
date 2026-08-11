#!/usr/bin/env bash
set -euo pipefail

./configure \
  --prefix=/usr \
  --disable-static \
  --without-python \
  --docdir="/usr/share/doc/libxslt-$PACKAGE_VERSION"
make -j"$JOBS"
make DESTDIR="$STAGE" install
