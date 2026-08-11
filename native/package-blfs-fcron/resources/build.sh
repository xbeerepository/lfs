#!/usr/bin/env bash
set -euo pipefail
find doc -type f -exec sed -i 's:/usr/local::g' {} \;
./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var --without-sendmail --with-piddir=/run --with-boot-install=no
make -j"$JOBS"

# Upstream's install helper prompts when the daemon account is absent.  The
# isolated builder does not run systemd-sysusers, so create the account with
# the same IDs declared below and keep installation fully non-interactive.
getent group fcron >/dev/null || groupadd --system --gid 22 fcron
getent passwd fcron >/dev/null || useradd --system --uid 22 --gid fcron \
  --home-dir /dev/null --shell /bin/false fcron

make DESTDIR="$STAGE" install
install -Dm644 /dev/null "$STAGE/usr/lib/sysusers.d/fcron.conf"
printf '%s\n' 'g fcron 22' 'u fcron 22 "Fcron User" /dev/null' >"$STAGE/usr/lib/sysusers.d/fcron.conf"
install -d "$STAGE/etc/systemd/system/multi-user.target.wants"
[ -e "$STAGE/usr/lib/systemd/system/fcron.service" ] && ln -sf /usr/lib/systemd/system/fcron.service "$STAGE/etc/systemd/system/multi-user.target.wants/fcron.service" || true
