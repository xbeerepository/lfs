#!/usr/bin/env bash
set -euo pipefail

make -j"$JOBS" \
  PREFIX=/usr \
  SYSCONFDIR=/etc/xdg \
  WAYLAND=1 \
  X11=0 \
  DUNSTIFY=1
make \
  PREFIX=/usr \
  SYSCONFDIR=/etc/xdg \
  DESTDIR="$STAGE" \
  WAYLAND=1 \
  X11=0 \
  DUNSTIFY=1 \
  install
