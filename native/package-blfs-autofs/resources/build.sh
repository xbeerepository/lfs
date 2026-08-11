#!/usr/bin/env bash
set -euo pipefail
./configure --prefix=/usr --with-mapdir=/etc/autofs --with-libtirpc \
  --with-systemd --without-openldap --mandir=/usr/share/man
make -j"$JOBS"
make DESTDIR="$STAGE" install
make DESTDIR="$STAGE" install_samples
install -d "$STAGE/etc/systemd/system/multi-user.target.wants"
ln -sf /usr/lib/systemd/system/autofs.service "$STAGE/etc/systemd/system/multi-user.target.wants/autofs.service"
test -x "$STAGE/usr/sbin/automount"
