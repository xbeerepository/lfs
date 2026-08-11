#!/usr/bin/env bash
set -euo pipefail
cmake -S . -B build -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release -DBUILD_GTK_TESTS=OFF -DBUILD_QT5_TESTS=OFF -DBUILD_QT6_TESTS=OFF -DENABLE_GLIB=ON -DENABLE_QT5=OFF -DENABLE_QT6=OFF -DENABLE_GPGME=OFF -DENABLE_BOOST=OFF -DENABLE_LIBCURL=OFF -DENABLE_NSS3=OFF -DENABLE_UNSTABLE_API_ABI_HEADERS=ON
cmake --build build -j"$JOBS"
DESTDIR="$STAGE" cmake --install build
test -x "$STAGE/usr/bin/pdfinfo"
test -e "$STAGE/usr/lib/pkgconfig/poppler-glib.pc"
