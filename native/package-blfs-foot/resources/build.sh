#!/usr/bin/env bash
set -euo pipefail

meson setup build \
  --prefix=/usr \
  --buildtype=release \
  --wrap-mode=nofallback \
  -Ddocs=disabled \
  -Dtests=false \
  -Dgrapheme-clustering=disabled \
  -Dutmp-backend=none
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install

# ncurses already ships the canonical Foot terminfo entries.  Keeping the
# copies installed by Foot would make the packages collide in the repository.
rm -f "$STAGE"/usr/share/terminfo/f/foot*
