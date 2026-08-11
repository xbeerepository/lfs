#!/usr/bin/env bash
set -euo pipefail

./configure \
  --prefix=/usr \
  --disable-static
make -j"$JOBS"
make DESTDIR="$STAGE" install

install -d "$STAGE/usr/share/doc/libpng-$PACKAGE_VERSION"
install -m 0644 README libpng-manual.txt \
  "$STAGE/usr/share/doc/libpng-$PACKAGE_VERSION/"
