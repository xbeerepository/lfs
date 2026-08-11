#!/usr/bin/env bash
set -euo pipefail
meson setup build \
  --prefix=/usr \
  --buildtype=release \
  -Dgtk_doc=false \
  -Dtests=false \
  -Dexamples=false \
  -Dbash_completion=false \
  -Dmbim=false \
  -Dqmi=false \
  -Dqrtr=false \
  -Dintrospection=false \
  -Dman=false
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
install -d "$STAGE/etc/systemd/system/multi-user.target.wants"
ln -sf /usr/lib/systemd/system/ModemManager.service "$STAGE/etc/systemd/system/multi-user.target.wants/ModemManager.service"
test -x "$STAGE/usr/bin/mmcli"
