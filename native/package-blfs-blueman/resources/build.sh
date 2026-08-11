#!/usr/bin/env bash
set -euo pipefail
./autogen.sh --prefix=/usr --sysconfdir=/etc --disable-schemas-compile --disable-caja-sendto --disable-nemo-sendto --disable-nautilus-sendto --enable-thunar-sendto
make -j"$JOBS"
make DESTDIR="$STAGE" install
test -x "$STAGE/usr/bin/blueman-manager"
