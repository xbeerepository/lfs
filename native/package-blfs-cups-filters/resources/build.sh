#!/usr/bin/env bash
set -euo pipefail
sed -i 's/\(char \*make_model\)/const \1/' backend/parallel.c
patch -Np1 -i /sources/cups-filters-2.0.1-security_fix-1.patch
sed -i 's/int (\*proc_func)()/int (*proc_func)(FILE *, FILE *, void *)/' \
  filter/foomatic-rip/process.c filter/foomatic-rip/process.h
sed -i 's/char modern_shell\[\] = SHELL;/char modern_shell[32] = SHELL;/' \
  filter/foomatic-rip/foomaticrip.c
./configure --prefix=/usr --disable-static --disable-mutool --docdir=/usr/share/doc/cups-filters-2.0.1
make -j"$JOBS"
make DESTDIR="$STAGE" install
test -x "$STAGE/usr/lib/cups/filter/pdftopdf"
