#!/usr/bin/env bash
set -euo pipefail
sed -i '4967,4968d' src/adapter.c
./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var --enable-library --disable-manpages
make -j"$JOBS"
make DESTDIR="$STAGE" install
install -d "$STAGE/usr/sbin"
ln -sf ../libexec/bluetooth/bluetoothd "$STAGE/usr/sbin/bluetoothd"
install -Dm644 src/main.conf "$STAGE/etc/bluetooth/main.conf"
install -d "$STAGE/etc/systemd/system/bluetooth.target.wants" "$STAGE/etc/systemd/user/default.target.wants"
ln -sf /usr/lib/systemd/system/bluetooth.service "$STAGE/etc/systemd/system/bluetooth.target.wants/bluetooth.service"
ln -sf /usr/lib/systemd/user/obex.service "$STAGE/etc/systemd/user/default.target.wants/obex.service"
test -x "$STAGE/usr/bin/bluetoothctl"
