#!/usr/bin/env bash
set -euo pipefail

meson setup build \
  --prefix=/usr \
  --buildtype=release \
  --wrap-mode=nofallback \
  -Dsession_tracking=logind \
  -Dauthfw=pam \
  -Dpam_include=system-auth \
  -Dpam_prefix=/etc/pam.d \
  -Dos_type=lfs \
  -Dpolkitd_user=polkitd \
  -Dsystemdsystemunitdir=/usr/lib/systemd/system \
  -Dintrospection=false \
  -Dgtk_doc=false \
  -Dman=false \
  -Dtests=false
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
