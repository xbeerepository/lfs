#!/usr/bin/env bash
set -euo pipefail
sed -i 's/catch_int ()/catch_int (int signum)/' test/poll.c
./configure --prefix=/usr --disable-static
make -j"$JOBS"
make DESTDIR="$STAGE" install
test -x "$STAGE/usr/bin/cdrskin"
