#!/usr/bin/env bash
set -euo pipefail
patch -Np1 -i /sources/cdparanoia-III-10.2-gcc_fixes-1.patch
./configure --prefix=/usr --mandir=/usr/share/man
make -j1
# This pre-DESTDIR Makefile writes directly to its configured directories.
# Override every install directory so packaging remains confined to the stage.
make \
  BINDIR="$STAGE/usr/bin" \
  MANDIR="$STAGE/usr/share/man" \
  INCLUDEDIR="$STAGE/usr/include" \
  LIBDIR="$STAGE/usr/lib" \
  install
chmod 755 "$STAGE"/usr/lib/libcdda_*.so.0.10.2
rm -f "$STAGE"/usr/lib/libcdda_*.a
test -x "$STAGE/usr/bin/cdparanoia"
