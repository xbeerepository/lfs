#!/usr/bin/env bash
set -euo pipefail
sed -i 's/static const/static/' libmpeg2/idct_mmx.c
./configure --prefix=/usr --enable-shared --disable-static
make -j"$JOBS"
make check
make DESTDIR="$STAGE" install
install -d "$STAGE/usr/share/doc/libmpeg2-0.5.1"
install -m644 README doc/libmpeg2.txt "$STAGE/usr/share/doc/libmpeg2-0.5.1/"
