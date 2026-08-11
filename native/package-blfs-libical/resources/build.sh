#!/usr/bin/env bash
set -euo pipefail
cmake -S . -B build -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release -DSHARED_ONLY=yes -DICAL_BUILD_DOCS=false -DGOBJECT_INTROSPECTION=false -DICAL_GLIB_VAPI=false
cmake --build build -j1
DESTDIR="$STAGE" cmake --install build
test -e "$STAGE/usr/lib/libical.so"
