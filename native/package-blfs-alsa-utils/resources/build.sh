#!/usr/bin/env bash
set -euo pipefail

sed -i 's/if (err)$/if (errcode)/; s/snd_strerror(err))/snd_strerror(errcode))/' \
  seq/aconnect/aconnect.c

./configure \
  --prefix=/usr \
  --disable-alsaconf \
  --disable-bat \
  --disable-xmlto \
  --with-curses=ncursesw
make -j"$JOBS"
make DESTDIR="$STAGE" install
