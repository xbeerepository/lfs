#!/usr/bin/env bash
set -euo pipefail
./configure --prefix=/usr --bindir=/usr/sbin --with-rpcuser=rpc --with-systemdsystemunitdir=/usr/lib/systemd/system
make -j"$JOBS"
make DESTDIR="$STAGE" install
install -Dm644 /dev/null "$STAGE/usr/lib/sysusers.d/rpcbind.conf"
printf '%s\n' 'u rpc 32 "RPC Bind Daemon" /var/lib/rpcbind' >"$STAGE/usr/lib/sysusers.d/rpcbind.conf"
