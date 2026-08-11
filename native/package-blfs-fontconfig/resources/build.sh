#!/usr/bin/env bash
set -euo pipefail

./configure \
  --prefix=/usr \
  --sysconfdir=/etc \
  --localstatedir=/var \
  --disable-docs \
  --docdir="/usr/share/doc/fontconfig-$PACKAGE_VERSION"
make -j"$JOBS"
make DESTDIR="$STAGE" install

install -d \
  "$STAGE/usr/share/man/man1" \
  "$STAGE/usr/share/man/man3" \
  "$STAGE/usr/share/man/man5" \
  "$STAGE/usr/share/doc/fontconfig-$PACKAGE_VERSION"
install -m 0644 fc-*/*.1 "$STAGE/usr/share/man/man1/"
install -m 0644 doc/*.3 "$STAGE/usr/share/man/man3/"
install -m 0644 doc/fonts-conf.5 "$STAGE/usr/share/man/man5/"
install -m 0644 doc/*.{pdf,sgml,txt,html} \
  "$STAGE/usr/share/doc/fontconfig-$PACKAGE_VERSION/"
