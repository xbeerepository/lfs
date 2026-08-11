#!/usr/bin/env bash
set -euo pipefail
make DESTDIR="$STAGE" install
install -d "$STAGE/etc/pki/anchors"
test -x "$STAGE/usr/sbin/make-ca"
