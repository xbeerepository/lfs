#!/usr/bin/env bash
set -euo pipefail

sed -r '/_GL_EXTERN_C/s/w?memchr|bsearch/(&)/' \
  -i $(find . -name '*.in.h')

./configure \
  --prefix=/usr \
  --disable-static \
  --docdir="/usr/share/doc/libunistring-$PACKAGE_VERSION"
make -j"$JOBS"
make DESTDIR="$STAGE" install
