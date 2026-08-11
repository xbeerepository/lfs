#!/usr/bin/env bash
set -euo pipefail
sed -i '/#include "parser_bison.h"/i #include <stdlib.h>' src/parser_bison.y
./configure --prefix=/usr --sysconfdir=/etc --disable-static --without-cli
make -j"$JOBS"
make DESTDIR="$STAGE" install
