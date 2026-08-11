#!/usr/bin/env bash
set -euo pipefail
cmake -S . -B _build -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release -DCMAKE_SKIP_INSTALL_RPATH=ON -DJAS_ENABLE_SHARED=ON -DJAS_ENABLE_DOC=OFF -DALLOW_IN_SOURCE_BUILD=YES -DCMAKE_INSTALL_DOCDIR=/usr/share/doc/jasper-4.2.8
cmake --build _build -j"$JOBS"
DESTDIR="$STAGE" cmake --install _build
test -x "$STAGE/usr/bin/jasper"
