#!/usr/bin/env bash
set -euo pipefail

patch -Np1 -i ../libcanberra-0.30-wayland-1.patch
./configure \
  --prefix=/usr \
  --disable-static \
  --disable-oss \
  --with-systemdsystemunitdir=/usr/lib/systemd/system
make -j"$JOBS"
make DESTDIR="$STAGE" docdir=/usr/share/doc/libcanberra-0.30 install
