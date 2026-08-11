#!/usr/bin/env bash
set -euo pipefail

perl Makefile.PL
make -j"$JOBS"
make DESTDIR="$STAGE" install

# ExtUtils::MakeMaker records every local installation in this shared file.
# It is host-local metadata, not part of XML::Parser, and collides with every
# other Perl module package when retained.
find "$STAGE" -type f -name perllocal.pod -delete
test -n "$(find "$STAGE" -path '*/XML/Parser.pm' -print -quit)"
