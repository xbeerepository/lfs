#!/usr/bin/env bash
set -euo pipefail

meson setup build --prefix=/usr --buildtype=release --wrap-mode=nofallback \
  -Ddoc=disabled \
  -Dintrospection=disabled \
  -Dtests=false \
  -Ddbus-tests=false \
  -Dsystem-lua=true \
  -Dsystemd=enabled \
  -Dsystemd-system-service=false \
  -Dsystemd-user-service=true
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install

install -d "$STAGE/etc/systemd/user/sockets.target.wants"
ln -s /usr/lib/systemd/user/pipewire.socket \
  "$STAGE/etc/systemd/user/sockets.target.wants/pipewire.socket"
ln -s /usr/lib/systemd/user/pipewire-pulse.socket \
  "$STAGE/etc/systemd/user/sockets.target.wants/pipewire-pulse.socket"
install -d "$STAGE/etc/systemd/user/graphical-session.target.wants"
ln -s /usr/lib/systemd/user/wireplumber.service \
  "$STAGE/etc/systemd/user/graphical-session.target.wants/wireplumber.service"
