#!/usr/bin/env bash
set -euo pipefail
export PATH="/opt/qt6/bin:$PATH"
export CMAKE_PREFIX_PATH="/opt/qt6${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"
export PKG_CONFIG_PATH="/opt/qt6/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
export LD_LIBRARY_PATH="/opt/qt6/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
meson setup build --prefix=/usr --buildtype=release -Dgtk=true -Dqt=true -Dbuildstamp=BLFS -Dlibarchive=true
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
# The plugins are a second source tree built in the same package. Expose the
# freshly staged core development files to their pkg-config and linker probes.
cp -a "$STAGE/usr/." /usr/
tar -xf /sources/audacious-plugins-4.5.1.tar.bz2 -C ..
cd ../audacious-plugins-4.5.1
meson setup build --prefix=/usr --buildtype=release -Dgtk=true -Dqt=true -Dwavpack=false -Dopus=false -Dgl-spectrum=false
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
test -x "$STAGE/usr/bin/audacious"
