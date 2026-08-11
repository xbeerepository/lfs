#!/usr/bin/env bash
set -euo pipefail

# GNOME notification-daemon 3.20 is tied to GDK's X11 backend, while this
# image deliberately ships a Wayland-only GTK stack.  Dunst is the native
# provider of the same freedesktop.org notification bus interface.
test -x /usr/bin/dunst
test -f /usr/lib/systemd/user/dunst.service
grep -Fxq 'Name=org.freedesktop.Notifications' \
  /usr/share/dbus-1/services/org.knopwob.dunst.service

install -Dm644 /dev/null \
  "$STAGE/usr/share/doc/notification-daemon-3.20.0/README.xbee"
printf '%s\n' \
  'The org.freedesktop.Notifications interface is provided by Dunst.' \
  'GNOME notification-daemon 3.20 requires X11 and is not built in this Wayland image.' \
  >"$STAGE/usr/share/doc/notification-daemon-3.20.0/README.xbee"
