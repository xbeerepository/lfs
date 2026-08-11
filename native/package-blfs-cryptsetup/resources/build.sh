#!/usr/bin/env bash
set -euo pipefail
./configure --prefix=/usr --disable-ssh-token --disable-asciidoc
make -j"$JOBS"
make DESTDIR="$STAGE" install
test -x "$STAGE/usr/sbin/cryptsetup"
