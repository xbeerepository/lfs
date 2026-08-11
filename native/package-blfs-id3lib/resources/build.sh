#!/usr/bin/env bash
set -euo pipefail

patch -Np1 -i /sources/id3lib-3.8.3-consolidated_patches-1.patch
libtoolize -fc
aclocal
autoconf
automake --add-missing --copy

./configure --prefix=/usr --disable-static
make -j"$JOBS"
make DESTDIR="$STAGE" install

install -d "$STAGE/usr/share/man/man1" "$STAGE/usr/share/doc/id3lib-3.8.3"
cp doc/man/* "$STAGE/usr/share/man/man1/"
install -m644 doc/*.{gif,jpg,png,ico,css,txt,php,html} \
  "$STAGE/usr/share/doc/id3lib-3.8.3/"
test -x "$STAGE/usr/bin/id3info"
test -e "$STAGE/usr/lib/libid3.so"
