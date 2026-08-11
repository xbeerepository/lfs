#!/usr/bin/env bash
set -euo pipefail
./configure --prefix=/usr --docdir=/usr/share/doc/acpid-2.0.34
make -j"$JOBS"
make DESTDIR="$STAGE" install
install -d "$STAGE/etc/acpi/events" "$STAGE/usr/share/doc/acpid-2.0.34"
cp -a samples "$STAGE/usr/share/doc/acpid-2.0.34/"
install -Dm644 /dev/null "$STAGE/usr/lib/systemd/system/acpid.socket"
cat >"$STAGE/usr/lib/systemd/system/acpid.socket" <<'EOF'
[Unit]
Description=ACPID socket
[Socket]
ListenStream=/run/acpid.socket
SocketMode=0666
[Install]
WantedBy=sockets.target
EOF
install -Dm644 /dev/null "$STAGE/usr/lib/systemd/system/acpid.service"
cat >"$STAGE/usr/lib/systemd/system/acpid.service" <<'EOF'
[Unit]
Description=ACPI event daemon
Requires=acpid.socket
[Service]
ExecStart=/usr/sbin/acpid -f
StandardInput=socket
EOF
install -d "$STAGE/etc/systemd/system/sockets.target.wants"
ln -sf /usr/lib/systemd/system/acpid.socket "$STAGE/etc/systemd/system/sockets.target.wants/acpid.socket"
