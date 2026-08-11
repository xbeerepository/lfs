#!/usr/bin/env bash
set -euo pipefail

sed -i \
  "/libpulse = dependency/a sndfile = dependency('sndfile', required: get_option('pulseaudio'))" \
  meson.build
sed -i '/        libpulse,/a\        sndfile,' meson.build

meson setup build --prefix=/usr --buildtype=release --wrap-mode=nofallback \
  -Dcava=disabled \
  -Ddbusmenu-gtk=disabled \
  -Dgps=disabled \
  -Djack=disabled \
  -Dlibevdev=enabled \
  -Dlibinput=enabled \
  -Dlibnl=enabled \
  -Dlibudev=enabled \
  -Dlogind=enabled \
  -Dman-pages=disabled \
  -Dmpd=disabled \
  -Dmpris=disabled \
  -Dpipewire=enabled \
  -Dpulseaudio=enabled \
  -Drfkill=enabled \
  -Dsndio=disabled \
  -Dsystemd=enabled \
  -Dtests=disabled \
  -Dupower_glib=disabled \
  -Dwireplumber=enabled
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
