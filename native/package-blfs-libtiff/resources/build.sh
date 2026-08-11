#!/usr/bin/env bash
set -euo pipefail

cmake -S . -B build -G Ninja \
  -D CMAKE_INSTALL_PREFIX=/usr \
  -D CMAKE_BUILD_TYPE=Release \
  -D CMAKE_INSTALL_LIBDIR=lib \
  -D CMAKE_SKIP_INSTALL_RPATH=ON
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
if [[ -d "$STAGE/usr/share/doc/tiff" ]]; then
  mv "$STAGE/usr/share/doc/tiff" "$STAGE/usr/share/doc/libtiff-$PACKAGE_VERSION"
fi
