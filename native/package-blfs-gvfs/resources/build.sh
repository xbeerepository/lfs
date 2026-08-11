#!/usr/bin/env bash
set -euo pipefail
meson setup build --prefix=/usr --buildtype=release -Donedrive=false -Dfuse=false -Dgphoto2=false -Dafc=false -Dbluray=false -Dnfs=false -Dmtp=false -Dsmb=false -Ddnssd=false -Dgoa=false -Dgoogle=false
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
test -e "$STAGE/usr/lib/gvfs/libgvfsdaemon.so"
