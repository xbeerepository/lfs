#!/usr/bin/env bash
set -euo pipefail
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
export QT6DIR=/opt/qt6
export PATH="$QT6DIR/bin:$PATH"
export LD_LIBRARY_PATH="$QT6DIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
sed -i 's@cert.pem@certs/ca-bundle.crt@' CMakeLists.txt
cmake -S . -B build -DCMAKE_INSTALL_PREFIX="$QT6DIR" -DCMAKE_BUILD_TYPE=Release -DQT6=ON -DQCA_INSTALL_IN_QT_PREFIX=ON -DQCA_MAN_INSTALL_DIR:PATH=/usr/share/man
cmake --build build -j"$JOBS"
DESTDIR="$STAGE" cmake --install build
test -x "$STAGE/opt/qt6/bin/qcatool-qt6"
