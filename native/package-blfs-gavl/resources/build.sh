#!/usr/bin/env bash
set -euo pipefail

sed -i '/stdio/a #include <string.h>' src/fill_test.c

LIBS=-lm ./configure \
  --prefix=/usr \
  --without-doxygen \
  --with-cpuflags=none \
  --docdir=/usr/share/doc/gavl-1.4.0
make -j"$JOBS"
test -f gavl/.libs/libgavl.so
make DESTDIR="$STAGE" install
