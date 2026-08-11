#!/usr/bin/env bash
set -euo pipefail
patch -Np1 -i /sources/gimp-3.0.6-security_fixes-1.patch
meson setup gimp-build --prefix=/usr --buildtype=release -Dheadless-tests=disabled
ninja -C gimp-build -j"$JOBS"
DESTDIR="$STAGE" ninja -C gimp-build install
test -x "$STAGE/usr/bin/gimp-3.0"
