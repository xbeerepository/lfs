#!/usr/bin/env bash
set -euo pipefail

./configure --prefix=/usr --disable-static
make -j"$JOBS"
make DESTDIR="$STAGE" install
find "$STAGE/usr/lib" -name '*.la' -delete
ln -sfn bsdunzip "$STAGE/usr/bin/unzip"
