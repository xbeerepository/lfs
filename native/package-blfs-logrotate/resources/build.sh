#!/usr/bin/env bash
set -euo pipefail
./configure --prefix=/usr
make -j"$JOBS"
make DESTDIR="$STAGE" install
install -d "$STAGE/etc/logrotate.d" "$STAGE/usr/lib/systemd/system" "$STAGE/etc/systemd/system/timers.target.wants"
cat >"$STAGE/etc/logrotate.conf" <<'EOF'
weekly
nomail
notifempty
rotate 2
create 0664 root sys
compress
include /etc/logrotate.d
EOF
cat >"$STAGE/usr/lib/systemd/system/logrotate.service" <<'EOF'
[Unit]
Description=Rotate log files
[Service]
Type=oneshot
ExecStart=/usr/sbin/logrotate /etc/logrotate.conf
EOF
cat >"$STAGE/usr/lib/systemd/system/logrotate.timer" <<'EOF'
[Unit]
Description=Daily log rotation
[Timer]
OnCalendar=*-*-* 3:00:00
Persistent=true
[Install]
WantedBy=timers.target
EOF
ln -sf /usr/lib/systemd/system/logrotate.timer "$STAGE/etc/systemd/system/timers.target.wants/logrotate.timer"
