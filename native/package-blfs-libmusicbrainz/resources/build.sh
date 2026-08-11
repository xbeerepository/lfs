#!/usr/bin/env bash
set -euo pipefail
patch -Np1 -i /sources/libmusicbrainz-5.1.0-cmake_fixes-1.patch
sed -e 's/xmlErrorPtr /const xmlError */' -i src/xmlParser.cc
cmake -S . -B build -D CMAKE_INSTALL_PREFIX=/usr -D CMAKE_BUILD_TYPE=Release -D CMAKE_POLICY_VERSION_MINIMUM=3.5
cmake --build build -j"$JOBS"
DESTDIR="$STAGE" cmake --install build
