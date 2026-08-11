#!/usr/bin/env bash
set -euo pipefail

cmake -S . -B build -G Ninja \
  -D CMAKE_INSTALL_PREFIX=/usr \
  -D CMAKE_BUILD_TYPE=RELEASE \
  -D ENABLE_STATIC=FALSE \
  -D CMAKE_INSTALL_DEFAULT_LIBDIR=lib \
  -D CMAKE_SKIP_INSTALL_RPATH=ON \
  -D CMAKE_INSTALL_DOCDIR="/usr/share/doc/libjpeg-turbo-$PACKAGE_VERSION"
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
