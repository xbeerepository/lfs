#!/usr/bin/env bash
set -euo pipefail

cd source
./configure --prefix=/usr
make -j"$JOBS"
make DESTDIR="$STAGE" install
