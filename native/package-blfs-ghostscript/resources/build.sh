#!/usr/bin/env bash
set -euo pipefail
rm -rf freetype lcms2mt jpeg libpng openjpeg zlib
./configure --prefix=/usr \
  --disable-compile-inits \
  --with-system-libtiff \
  --without-tesseract
make -j"$JOBS"
make DESTDIR="$STAGE" install
make DESTDIR="$STAGE" soinstall
test -x "$STAGE/usr/bin/gs"
