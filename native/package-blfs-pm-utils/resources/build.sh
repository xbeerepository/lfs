#!/usr/bin/env bash
set -euo pipefail
patch -Np1 -i /sources/pm-utils-1.4.1-bugfixes-1.patch
./configure --prefix=/usr --sysconfdir=/etc
make -j"$JOBS"
make DESTDIR="$STAGE" install
test -L "$STAGE/usr/sbin/pm-suspend"
test "$(readlink "$STAGE/usr/sbin/pm-suspend")" = /usr/lib/pm-utils/bin/pm-action
test -x "$STAGE/usr/lib/pm-utils/bin/pm-action"
