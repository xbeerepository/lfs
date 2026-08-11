#!/usr/bin/env bash
set -euo pipefail
patch -Np1 -i /sources/libmad-0.15.1b-fixes-1.patch
sed 's@AM_CONFIG_HEADER@AC_CONFIG_HEADERS@g' -i configure.ac
touch NEWS AUTHORS ChangeLog
autoreconf -fi
./configure --prefix=/usr --disable-static
make -j"$JOBS"
make DESTDIR="$STAGE" install
install -d "$STAGE/usr/lib/pkgconfig"
cat >"$STAGE/usr/lib/pkgconfig/mad.pc" <<'EOF'
prefix=/usr
exec_prefix=${prefix}
libdir=${exec_prefix}/lib
includedir=${prefix}/include

Name: mad
Description: MPEG audio decoder
Version: 0.15.1b
Libs: -L${libdir} -lmad
Cflags: -I${includedir}
EOF
