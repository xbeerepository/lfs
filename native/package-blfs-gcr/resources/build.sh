#!/usr/bin/env bash
set -euo pipefail
meson setup build --prefix=/usr --buildtype=release \
  -Dgtk_doc=false -Dvapi=false -Dssh_agent=false -Dsystemd=disabled \
  -Dgpg_path=/usr/bin/gpg
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
test -e "$STAGE/usr/lib/libgcr-4.so"
