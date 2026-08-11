#!/usr/bin/env bash
set -euo pipefail
sa_lib_dir=/usr/lib/sa sa_dir=/var/log/sa conf_dir=/etc/sysconfig ./configure --prefix=/usr --disable-file-attr
make -j"$JOBS"
make DESTDIR="$STAGE" install
test -x "$STAGE/usr/bin/iostat"
