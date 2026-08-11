#!/usr/bin/env bash
set -euo pipefail
./configure --prefix=/usr --sysconfdir=/etc --enable-hdri --with-modules --with-perl --disable-static
make -j"$JOBS"
make DESTDIR="$STAGE" DOCUMENTATION_PATH=/usr/share/doc/imagemagick-7.1.2 install
test -x "$STAGE/usr/bin/magick"
