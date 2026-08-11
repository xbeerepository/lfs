#!/usr/bin/env bash
set -euo pipefail
./configure --prefix=/usr --disable-rpath --bundled-libraries=NONE
make -j"$JOBS"
make DESTDIR="$STAGE" install
