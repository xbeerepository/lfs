#!/usr/bin/env bash
set -euo pipefail
./configure --prefix=/usr --with-ssl --enable-shared --disable-static
make -j"$JOBS"
make check
make DESTDIR="$STAGE" install
