#!/usr/bin/env bash
set -euo pipefail

sed -i '/typedef enum/,/bool ;/d' src/ALAC/alac_{en,de}coder.c
sed -i '/#include "EndianPortable.h"/a #include <stdbool.h>' \
  src/ALAC/alac_{en,de}coder.c
CFLAGS="-O2 -std=gnu17" ./configure \
  --prefix=/usr \
  --disable-static \
  --disable-mpeg \
  --disable-full-suite
make -j"$JOBS"
make check
make DESTDIR="$STAGE" install
