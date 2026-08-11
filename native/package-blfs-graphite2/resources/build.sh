#!/usr/bin/env bash
set -euo pipefail

sed -i '/cmptest/d' tests/CMakeLists.txt
sed -i '/cmake_policy(SET CMP0012 NEW)/d' CMakeLists.txt
sed -i 's/PythonInterp/Python3/' CMakeLists.txt
find . -name CMakeLists.txt -exec \
  sed -i 's/VERSION 2.8.0 FATAL_ERROR/VERSION 4.0.0/' {} +
sed -i '/Font.h/i #include <cstdint>' \
  tests/featuremap/featuremaptest.cpp

cmake -S . -B build \
  -D CMAKE_INSTALL_PREFIX=/usr \
  -D CMAKE_BUILD_TYPE=Release
cmake --build build --parallel "$JOBS"
DESTDIR="$STAGE" cmake --install build
