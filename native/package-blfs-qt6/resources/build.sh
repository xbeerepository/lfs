#!/usr/bin/env bash
set -euo pipefail

export QT6PREFIX=/opt/qt6

./configure \
  -prefix "$QT6PREFIX" \
  -sysconfdir /etc/xdg \
  -dbus-linked \
  -openssl-linked \
  -system-sqlite \
  -nomake examples \
  -no-rpath \
  -no-sbom \
  -journald \
  -skip qt3d \
  -skip qtquick3dphysics \
  -skip qtwebengine \
  -no-feature-xcb
ninja -j"$JOBS"
DESTDIR="$STAGE" ninja install

find "$STAGE$QT6PREFIX" -name '*.prl' -exec sed -i '/^QMAKE_PRL_BUILD_DIR/d' {} +
install -Dm644 /dev/null "$STAGE/etc/ld.so.conf.d/qt6.conf"
printf '%s\n' '/opt/qt6/lib' > "$STAGE/etc/ld.so.conf.d/qt6.conf"
install -Dm644 /dev/null "$STAGE/etc/profile.d/qt6.sh"
printf '%s\n' \
  'QT6DIR=/opt/qt6' \
  'export QT6DIR' \
  'export PATH="$QT6DIR/bin:$PATH"' \
  'export PKG_CONFIG_PATH="$QT6DIR/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"' \
  > "$STAGE/etc/profile.d/qt6.sh"
test -x "$STAGE/opt/qt6/bin/qtpaths6"
