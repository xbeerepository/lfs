#!/usr/bin/env bash
set -euo pipefail
make prefix=/usr DESTDIR="$STAGE" install
test -d "$STAGE/usr/share/poppler/cMap"
