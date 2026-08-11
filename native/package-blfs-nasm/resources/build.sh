#!/usr/bin/env bash
set -euo pipefail

./configure --prefix=/usr
make -j"$JOBS"
make DESTDIR="$STAGE" install
