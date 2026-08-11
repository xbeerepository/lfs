#!/usr/bin/env bash
set -euo pipefail
patch -Np1 -i /sources/itstool-2.0.7-lxml-1.patch
PYTHON=/usr/bin/python3 ./autogen.sh --prefix=/usr
make -j"$JOBS"
make DESTDIR="$STAGE" install
test -x "$STAGE/usr/bin/itstool"
