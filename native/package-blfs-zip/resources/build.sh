#!/usr/bin/env bash
set -euo pipefail
make -f unix/Makefile generic CC='gcc -std=gnu89' -j"$JOBS"
make prefix="$STAGE/usr" MANDIR="$STAGE/usr/share/man/man1" -f unix/Makefile install
test -x "$STAGE/usr/bin/zip"
