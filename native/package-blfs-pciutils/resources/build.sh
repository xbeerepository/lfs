#!/usr/bin/env bash
set -euo pipefail
sed -r '/INSTALL/{/PCI_IDS|update-pciids /d; s/update-pciids.8//}' -i Makefile
make PREFIX=/usr SHAREDIR=/usr/share/hwdata SHARED=yes -j"$JOBS"
make PREFIX="$STAGE/usr" SHAREDIR="$STAGE/usr/share/hwdata" SHARED=yes install install-lib
chmod 755 "$STAGE/usr/lib/libpci.so"
test -x "$STAGE/usr/bin/lspci"
