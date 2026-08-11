#!/usr/bin/env bash
set -euo pipefail
perl Makefile.PL
make -j"$JOBS"
make test
make DESTDIR="$STAGE" install
find "$STAGE" -type f -name perllocal.pod -delete
test -n "$(find "$STAGE" -path '*/Parse/Yapp/Driver.pm' -print -quit)"
