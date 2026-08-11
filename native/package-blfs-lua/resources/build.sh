#!/usr/bin/env bash
set -euo pipefail

patch -Np1 -i /sources/lua-5.4.8-shared_library-1.patch
make -j"$JOBS" linux
make \
  INSTALL_TOP="$STAGE/usr" \
  INSTALL_DATA="cp -d" \
  INSTALL_MAN="$STAGE/usr/share/man/man1" \
  TO_LIB="liblua.so liblua.so.5.4 liblua.so.5.4.8" \
  install

install -d "$STAGE/usr/lib/pkgconfig"
cat >"$STAGE/usr/lib/pkgconfig/lua.pc" <<'EOF'
V=5.4
R=5.4.8
prefix=/usr
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include
Name: Lua
Description: An Extensible Extension Language
Version: ${R}
Libs: -L${libdir} -llua -lm -ldl
Cflags: -I${includedir}
EOF
