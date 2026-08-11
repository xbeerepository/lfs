#!/usr/bin/env bash
set -euo pipefail

patch -Np1 -i ../sgml-common-0.6.3-manpage-1.patch
autoreconf -f -i
./configure --prefix=/usr --sysconfdir=/etc
make -j"$JOBS"
make DESTDIR="$STAGE" docdir=/usr/share/doc install

printf '%s\n' \
  'CATALOG /usr/share/sgml/sgml-iso-entities-8879.1986/catalog' \
  >"$STAGE/etc/sgml/sgml-ent.cat"
printf '%s\n' \
  'CATALOG /etc/sgml/sgml-ent.cat' \
  >"$STAGE/etc/sgml/sgml-docbook.cat"
printf '%s\n' \
  'CATALOG /etc/sgml/sgml-ent.cat' \
  'CATALOG /etc/sgml/sgml-docbook.cat' \
  >"$STAGE/etc/sgml/catalog"
