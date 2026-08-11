#!/usr/bin/env bash
set -euo pipefail
./configure --prefix=/usr --disable-static --docdir=/usr/share/doc/libsamplerate-0.2.2
make -j"$JOBS"
make check
make DESTDIR="$STAGE" install
