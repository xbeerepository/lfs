#!/usr/bin/env bash
set -euo pipefail
./configure --prefix=/usr --sysconfdir=/etc --with-python3 --without-escrow --without-gtk-doc --without-lvm_dbus --without-nvdimm --without-smartmontools
make -j"$JOBS"
make DESTDIR="$STAGE" install
test -e "$STAGE/usr/lib/libblockdev.so"
