#!/usr/bin/env bash
set -euo pipefail
./configure --prefix=/usr --sysconfdir=/etc --sbindir=/usr/sbin --disable-gss --without-tcp-wrappers
make -j"$JOBS"
make DESTDIR="$STAGE" install
test -x "$STAGE/sbin/mount.nfs"
