#!/usr/bin/env bash
set -euo pipefail
sed -e '/^extern int (\*xstat)/s/()/(const char * restrict,  struct stat * restrict)/' -i src/extern.h
sed -e '/^int (\*xstat)/s/()/(const char * restrict,  struct stat * restrict)/' -i src/global.c
./configure --prefix=/usr --enable-mt --with-rmt=/usr/libexec/rmt
make -j"$JOBS"
make DESTDIR="$STAGE" install
test -x "$STAGE/usr/bin/cpio"
