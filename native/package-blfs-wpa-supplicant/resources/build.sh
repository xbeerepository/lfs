#!/usr/bin/env bash
set -euo pipefail

cp wpa_supplicant/defconfig wpa_supplicant/.config
cat >>wpa_supplicant/.config <<'EOF'
CONFIG_CTRL_IFACE=y
CONFIG_DRIVER_NL80211=y
CONFIG_DRIVER_WIRED=y
CONFIG_LIBNL32=y
CONFIG_READLINE=y
CONFIG_CTRL_IFACE_DBUS=y
CONFIG_CTRL_IFACE_DBUS_NEW=y
CONFIG_CTRL_IFACE_DBUS_INTRO=y
CFLAGS += -I/usr/include/libnl3
EOF
make -C wpa_supplicant -j"$JOBS" BINDIR=/usr/sbin LIBDIR=/usr/lib
install -Dm755 wpa_supplicant/wpa_supplicant "$STAGE/usr/sbin/wpa_supplicant"
install -Dm755 wpa_supplicant/wpa_cli "$STAGE/usr/sbin/wpa_cli"
install -Dm755 wpa_supplicant/wpa_passphrase "$STAGE/usr/sbin/wpa_passphrase"
install -Dm644 wpa_supplicant/dbus/fi.w1.wpa_supplicant1.service \
  "$STAGE/usr/share/dbus-1/system-services/fi.w1.wpa_supplicant1.service"
install -Dm644 wpa_supplicant/dbus/dbus-wpa_supplicant.conf \
  "$STAGE/etc/dbus-1/system.d/wpa_supplicant.conf"
install -d "$STAGE/usr/lib/systemd/system"
install -m644 wpa_supplicant/systemd/*.service "$STAGE/usr/lib/systemd/system/"
