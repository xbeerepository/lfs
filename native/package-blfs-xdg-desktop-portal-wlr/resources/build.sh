#!/usr/bin/env bash
set -euo pipefail

meson setup build --prefix=/usr --buildtype=release --wrap-mode=nofallback
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install

install -d "$STAGE/usr/share/xdg-desktop-portal"
for desktop in sway wlr; do
  printf '%s\n' \
    '[preferred]' \
    'default=gtk' \
    'org.freedesktop.impl.portal.ScreenCast=wlr' \
    'org.freedesktop.impl.portal.Screenshot=wlr' \
    > "$STAGE/usr/share/xdg-desktop-portal/${desktop}-portals.conf"
done
