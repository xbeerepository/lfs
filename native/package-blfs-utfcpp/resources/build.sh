#!/usr/bin/env bash
set -euo pipefail
cmake -S . -B build -DCMAKE_INSTALL_PREFIX=/usr
DESTDIR="$STAGE" cmake --install build
test -d "$STAGE/usr/include/utf8cpp"
