#!/usr/bin/env bash
set -euo pipefail
./configure --prefix=/usr --disable-static --docdir=/usr/share/doc/gnutls-3.8.12 --with-default-trust-store-pkcs11='pkcs11:'
make -j"$JOBS"
make DESTDIR="$STAGE" install
test -e "$STAGE/usr/lib/libgnutls.so"
