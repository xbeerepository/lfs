#!/usr/bin/env bash
set -euo pipefail

./configure --prefix=/usr
make -j"$JOBS"
make DESTDIR="$STAGE" install

# Preserve the merged-/usr layout: /lib is a symlink to /usr/lib in the
# assembled system and must not become a separate package-owned directory.
if [[ -d "$STAGE/lib/firmware" ]]; then
  install -d "$STAGE/usr/lib"
  mv "$STAGE/lib/firmware" "$STAGE/usr/lib/firmware"
  rmdir "$STAGE/lib"
fi
