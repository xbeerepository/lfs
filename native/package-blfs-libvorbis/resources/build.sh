#!/usr/bin/env bash
set -euo pipefail

./configure --prefix=/usr --disable-static
make -j"$JOBS"
make -j1 check
make DESTDIR="$STAGE" install
install -d "$STAGE/usr/share/doc/libvorbis-1.3.7"
install -m 0644 doc/Vorbis* "$STAGE/usr/share/doc/libvorbis-1.3.7/"
