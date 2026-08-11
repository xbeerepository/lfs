#!/usr/bin/env bash
set -euo pipefail
sed -i '/"lib64"/s/64//' kde-modules/KDEInstallDirsCommon.cmake
sed -e '/PACKAGE_INIT/i set(SAVE_PACKAGE_PREFIX_DIR "${PACKAGE_PREFIX_DIR}")' -e '/^include/a set(PACKAGE_PREFIX_DIR "${SAVE_PACKAGE_PREFIX_DIR}")' -i ECMConfig.cmake.in
cmake -S . -B build -DCMAKE_INSTALL_PREFIX=/usr -DBUILD_WITH_QT6=ON -DDOC_INSTALL_DIR=/usr/share/doc/extra-cmake-modules-6.23.0
cmake --build build -j"$JOBS"
DESTDIR="$STAGE" cmake --install build
test -d "$STAGE/usr/share/ECM"
