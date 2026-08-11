#!/usr/bin/env bash
set -euo pipefail
sed -r '/cmake_policy.*(0025|0054)/d' -i source/CMakeLists.txt
cmake -S source -B build -DCMAKE_INSTALL_PREFIX=/usr -DGIT_ARCHETYPE=1 -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -Wno-dev
cmake --build build -j"$JOBS"
DESTDIR="$STAGE" cmake --install build
rm -f "$STAGE/usr/lib/libx265.a"
test -x "$STAGE/usr/bin/x265"
