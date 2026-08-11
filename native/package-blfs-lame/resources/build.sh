#!/usr/bin/env bash
set -euo pipefail
sed -i -e 's/^\(\s*hardcode_libdir_flag_spec\s*=\).*/\1/' configure
./configure --prefix=/usr --enable-mp3rtp --disable-static
make -j"$JOBS"
LD_LIBRARY_PATH=libmp3lame/.libs make test
make DESTDIR="$STAGE" pkghtmldir=/usr/share/doc/lame-3.100 install
test -x "$STAGE/usr/bin/lame"
