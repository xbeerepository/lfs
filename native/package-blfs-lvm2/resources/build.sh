#!/usr/bin/env bash
set -euo pipefail
PATH="$PATH:/usr/sbin" ./configure --prefix=/usr --enable-cmdlib --enable-pkgconfig --enable-udev_sync
make -j"$JOBS"
make DESTDIR="$STAGE" install
make DESTDIR="$STAGE" install_systemd_units
sed -e '/locking_dir =/{s/#//;s/var/run/}' -i "$STAGE/etc/lvm/lvm.conf"
test -x "$STAGE/usr/sbin/lvm"
