#!/usr/bin/env bash
set -euo pipefail

sed -i '/"lib64"/s/64//' Modules/GNUInstallDirs.cmake
MAKEFLAGS="-j$JOBS" ./bootstrap \
  --prefix=/usr \
  --system-libs \
  --no-system-curl \
  --mandir=/share/man \
  --no-system-jsoncpp \
  --no-system-cppdap \
  --no-system-librhash \
  --no-system-libuv \
  --docdir="/share/doc/cmake-$PACKAGE_VERSION"
make -j"$JOBS"
make DESTDIR="$STAGE" install
