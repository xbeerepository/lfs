#!/usr/bin/env bash
set -euo pipefail

meson setup build --prefix=/usr --buildtype=release --wrap-mode=nofallback \
  --auto-features=disabled \
  -Ddocs=disabled \
  -Dman=disabled \
  -Dexamples=disabled \
  -Dtests=disabled \
  -Dinstalled_tests=disabled \
  -Dspa-plugins=enabled \
  -Dalsa=enabled \
  -Dbluez5=enabled \
  -Daudiomixer=enabled \
  -Daudioconvert=enabled \
  -Dcontrol=enabled \
  -Dsupport=enabled \
  -Ddbus=enabled \
  -Dlibsystemd=enabled \
  -Dlogind=enabled \
  -Dsystemd-user-service=enabled \
  -Dudev=enabled \
  -Dsndfile=enabled \
  -Dreadline=enabled \
  -Dpipewire-alsa=enabled \
  -Dpipewire-jack=disabled \
  -Dpipewire-v4l2=disabled \
  -Dflatpak=disabled \
  -Dsession-managers=[]
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
