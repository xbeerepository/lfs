#!/usr/bin/env bash
set -euo pipefail

./bootstrap
./configure \
  --prefix=/usr \
  --disable-static
make -j"$JOBS"

./frontend/faac \
  -o /tmp/faac-Front_Left.mp4 \
  /usr/share/sounds/alsa/Front_Left.wav
test -s /tmp/faac-Front_Left.mp4
rm -f /tmp/faac-Front_Left.mp4

make DESTDIR="$STAGE" install
