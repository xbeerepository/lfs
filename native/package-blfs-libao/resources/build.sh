#!/usr/bin/env bash
set -euo pipefail
sed -i '/limits.h/a #include <time.h>' src/plugins/pulse/ao_pulse.c
./configure --prefix=/usr
make -j"$JOBS"
make DESTDIR="$STAGE" install
install -Dm644 README "$STAGE/usr/share/doc/libao-1.2.0/README"
