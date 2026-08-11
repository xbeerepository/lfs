#!/usr/bin/env bash
set -euo pipefail
./configure --with-daemon_username=atd --with-daemon_groupname=atd \
  SENDMAIL=/usr/sbin/sendmail --with-jobdir=/var/spool/atjobs \
  --with-atspool=/var/spool/atspool --with-systemdsystemunitdir=/usr/lib/systemd/system
make -j1

# The upstream install target resolves the daemon account while assigning the
# spool directories.  The isolated builder does not run systemd-sysusers, so
# provide the same account temporarily; the packaged sysusers file remains the
# source of truth on the installed system.
getent group atd >/dev/null || groupadd --system --gid 17 atd
getent passwd atd >/dev/null || useradd --system --uid 17 --gid atd \
  --home-dir /dev/null --shell /bin/false atd

make DESTDIR="$STAGE" docdir=/usr/share/doc/at-3.2.5 atdocdir=/usr/share/doc/at-3.2.5 install
install -Dm644 /dev/null "$STAGE/usr/lib/sysusers.d/at.conf"
printf '%s\n' 'g atd 17' 'u atd 17 "atd daemon" /dev/null' >"$STAGE/usr/lib/sysusers.d/at.conf"
install -Dm644 /dev/null "$STAGE/usr/lib/tmpfiles.d/at.conf"
printf '%s\n' 'd /var/spool/atjobs 0700 atd atd -' 'd /var/spool/atspool 0700 atd atd -' >"$STAGE/usr/lib/tmpfiles.d/at.conf"
install -d "$STAGE/etc/systemd/system/multi-user.target.wants"
ln -sf /usr/lib/systemd/system/atd.service "$STAGE/etc/systemd/system/multi-user.target.wants/atd.service"
