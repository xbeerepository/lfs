#!/usr/bin/env bash
set -euo pipefail

sed -e 's/GROUP="render"/GROUP="video"/' \
    -e 's/GROUP="sgx", //' \
    -i rules.d/50-udev-default.rules.in

meson setup build \
  --prefix=/usr \
  --buildtype=release \
  --wrap-mode=nofallback \
  -D default-dnssec=no \
  -D firstboot=false \
  -D install-tests=false \
  -D ldconfig=false \
  -D sysusers=false \
  -D rpmmacrosdir=no \
  -D homed=disabled \
  -D man=disabled \
  -D mode=release \
  -D pam=enabled \
  -D pamconfdir=/etc/pam.d \
  -D dev-kvm-mode=0660 \
  -D nobody-group=nogroup \
  -D sysupdate=disabled \
  -D ukify=disabled \
  -D docdir="/usr/share/doc/systemd-$PACKAGE_VERSION"
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install

install -d "$STAGE/usr/share/man"
tar -xf /sources/systemd-man-pages-259.1.tar.xz \
  --no-same-owner --strip-components=1 \
  -C "$STAGE/usr/share/man"
