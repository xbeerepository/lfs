#!/usr/bin/env bash
set -euo pipefail
# Thunar 4.20 makes Xlib mandatory in configure even though the only
# unconditional X11 consumer is the optional wallpaper plug-in.  This image
# deliberately provides a Wayland-only GTK build, so keep X11/XSMP disabled.
sed -i 's/as_fn_error $? "X Window system libraries and header files are required"/: "X Window system libraries and header files are not available"/' configure
sed -i '/^#include <gdk\/gdkx.h>$/d' thunar/thunar-session-client.c
./configure --prefix=/usr --sysconfdir=/etc --docdir=/usr/share/doc/thunar-4.20.7 --disable-wallpaper-plugin
make -j"$JOBS"
make DESTDIR="$STAGE" install
test -x "$STAGE/usr/bin/thunar"
