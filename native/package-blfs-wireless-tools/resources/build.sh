#!/usr/bin/env bash
set -euo pipefail
patch -Np1 -i /sources/wireless_tools-29-fix_iwlist_scanning-1.patch
make -j"$JOBS"
make PREFIX="$STAGE/usr" INSTALL_MAN="$STAGE/usr/share/man" install
test -x "$STAGE/usr/sbin/iwconfig"
