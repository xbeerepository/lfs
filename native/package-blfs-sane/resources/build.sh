#!/usr/bin/env bash
set -euo pipefail
./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var --with-lockdir=/run/lock --docdir=/usr/share/doc/sane-backends-1.4.0 --enable-libusb_1_0
make -j"$JOBS"
make DESTDIR="$STAGE" install
install -Dm644 tools/udev/libsane.rules "$STAGE/usr/lib/udev/rules.d/70-scanner.rules"
install -Dm644 /dev/null "$STAGE/usr/lib/sysusers.d/sane.conf"
printf '%s\n' 'g scanner -' > "$STAGE/usr/lib/sysusers.d/sane.conf"
test -x "$STAGE/usr/bin/scanimage"
