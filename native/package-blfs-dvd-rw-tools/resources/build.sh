#!/usr/bin/env bash
set -euo pipefail
patch -Np1 -i /sources/dvd+rw-tools-7.1-consolidated_fixes-2.patch
make -j"$JOBS" all rpl8 btcflash
make prefix="$STAGE/usr" install
# cdrtools, an explicit runtime dependency, already provides btcflash.
# Keeping the second byte-identical command would create dual ownership.
rm -f "$STAGE/usr/bin/btcflash"
test -x "$STAGE/usr/bin/growisofs"
