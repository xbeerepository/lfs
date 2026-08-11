#!/usr/bin/env bash
set -euo pipefail

sed -i 's/-Os/-O2/' Makefile.sharedlibrary
make -f Makefile.sharedlibrary -j"$JOBS" INSTALL_PREFIX=/usr
make -f Makefile.sharedlibrary INSTALL_PREFIX=/usr DESTDIR="$STAGE" install
