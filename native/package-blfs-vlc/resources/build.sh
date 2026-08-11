#!/usr/bin/env bash
set -euo pipefail
export PATH="/opt/qt6/bin:$PATH"
export PKG_CONFIG_PATH="/opt/qt6/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
export LD_LIBRARY_PATH="/opt/qt6/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
rm -f /usr/lib/libarchive.la
sed -i 's/gstvideopool.h/video.h/' modules/codec/gstreamer/gstvlcvideopool.h
BUILDCC=gcc ./configure --prefix=/usr --disable-xcb
make -j"$JOBS"
make DESTDIR="$STAGE" docdir=/usr/share/doc/vlc-3.0.23 install
test -x "$STAGE/usr/bin/vlc"
