#!/usr/bin/env bash
set -euo pipefail
meson setup build --prefix=/usr --buildtype=release -Dgtk_doc=false -Dtests=false
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
install -d "$STAGE/etc/systemd/system/multi-user.target.wants"
ln -sf /usr/lib/systemd/system/power-profiles-daemon.service \
  "$STAGE/etc/systemd/system/multi-user.target.wants/power-profiles-daemon.service"
test -x "$STAGE/usr/bin/powerprofilesctl"
