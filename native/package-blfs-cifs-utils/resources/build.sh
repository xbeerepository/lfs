#!/usr/bin/env bash
set -euo pipefail
ac_cv_header_stdbool_h=yes \
  ./configure --prefix=/usr --sbindir=/usr/sbin
make -j"$JOBS"
make DESTDIR="$STAGE" install
install -d "$STAGE/usr/sbin"
mv "$STAGE/sbin/mount.cifs" "$STAGE/sbin/mount.smb3" "$STAGE/usr/sbin/"
rmdir "$STAGE/sbin"
test -x "$STAGE/usr/sbin/mount.cifs"
