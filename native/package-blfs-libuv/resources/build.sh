#!/usr/bin/env bash
set -euo pipefail
sh autogen.sh
./configure --prefix=/usr --disable-static
make -j"$JOBS"
make DESTDIR="$STAGE" install
