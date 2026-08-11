#!/usr/bin/env bash
set -euo pipefail
perl Makefile.PL
make -j"$JOBS"
# Three upstream tests need Test::Fatal/Test::Needs/Test::Warnings, which are
# test-only CPAN modules not shipped by BLFS.  Run the complete self-contained
# suite instead of dropping all package testing.
mapfile -t tests < <(find t -maxdepth 1 -name '*.t' \
  ! -name 'escape.t' ! -name 'storable.t' ! -name 'urn-isbn.t' | sort)
prove -b "${tests[@]}"
make DESTDIR="$STAGE" install
find "$STAGE" -type f -name perllocal.pod -delete
test -n "$(find "$STAGE" -path '*/URI.pm' -print -quit)"
