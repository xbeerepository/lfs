#!/usr/bin/env bash
set -euo pipefail
sed -i 's/do_version ()/do_version (PedDevice** dev, PedDisk** diskp)/' parted/parted.c
./configure --prefix=/usr --disable-static
make -j"$JOBS"
make DESTDIR="$STAGE" install
test -x "$STAGE/usr/sbin/parted"
