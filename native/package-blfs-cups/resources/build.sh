#!/usr/bin/env bash
set -euo pipefail
sed -i '/& ipp->prev)/s/prev/& \&\& ipp->prev->next == *attr/' cups/ipp.c
./configure --prefix=/usr --libdir=/usr/lib --sysconfdir=/etc --localstatedir=/var --with-rundir=/run/cups --with-system-groups=lpadmin --with-docdir=/usr/share/cups/doc-2.4.16
make -j"$JOBS"
make BUILDROOT="$STAGE" install
install -Dm644 /dev/null "$STAGE/usr/lib/sysusers.d/cups.conf"
printf '%s\n' 'g lpadmin -' 'u lp - "CUPS scheduler" /var/spool/cups' > "$STAGE/usr/lib/sysusers.d/cups.conf"
test -x "$STAGE/usr/sbin/cupsd"
