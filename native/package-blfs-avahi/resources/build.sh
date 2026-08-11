#!/usr/bin/env bash
set -euo pipefail
patch -Np1 -i /sources/avahi-0.8-ipv6_race_condition_fix-1.patch
sed -i '426a if (events & AVAHI_WATCH_HUP) { client_free(c); return; }' avahi-daemon/simple-protocol.c
./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var --disable-static --disable-libevent --disable-qt3 --disable-qt4 --disable-qt5 --disable-gtk --disable-gtk3 --disable-gdbm --disable-python --disable-mono --disable-monodoc --with-distro=none --with-dbus-system-address='unix:path=/run/dbus/system_bus_socket'
make -j"$JOBS"
make DESTDIR="$STAGE" install
install -Dm644 /dev/null "$STAGE/usr/lib/sysusers.d/avahi.conf"
printf '%s\n' 'u avahi - "Avahi mDNS daemon" /run/avahi-daemon' 'u avahi-autoipd - "Avahi IPv4LL daemon" /run/avahi-autoipd' > "$STAGE/usr/lib/sysusers.d/avahi.conf"
test -x "$STAGE/usr/sbin/avahi-daemon"
