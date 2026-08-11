#!/usr/bin/env bash
set -euo pipefail

./configure --prefix=/usr --disable-blacklist
make DESTDIR="$STAGE" install
