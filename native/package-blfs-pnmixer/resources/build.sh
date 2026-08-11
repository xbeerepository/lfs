#!/usr/bin/env bash
set -euo pipefail
cmake -S . -B build -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_POLICY_VERSION_MINIMUM=3.5
cmake --build build -j"$JOBS"
DESTDIR="$STAGE" cmake --install build
test -x "$STAGE/usr/bin/pnmixer"
