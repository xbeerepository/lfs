#!/usr/bin/env bash
set -euo pipefail
sed -i 's|/opt/schily|/usr|g' DEFAULTS/Defaults.linux
sed -i 's|DEFINSGRP=.*|DEFINSGRP=root|' DEFAULTS/Defaults.linux
sed -i 's|INSDIR=\\s*sbin|INSDIR=bin|' rscsi/Makefile
export GMAKE_NOWARN=true
export CFLAGS="${CFLAGS:-} -std=gnu89 -fno-strict-aliasing"
make -j1 INS_BASE=/usr DEFINSUSR=root DEFINSGRP=root VERSION_OS=LinuxFromScratch
make INS_BASE="$STAGE/usr" DEFINSUSR=root DEFINSGRP=root MANSUFF_LIB=3cdr install
test -x "$STAGE/usr/bin/cdrecord"
