#!/usr/bin/env bash
set -euo pipefail

patch -Np1 -i /sources/audiofile-0.3.6-consolidated_patches-1.patch
autoreconf -fiv

shared_dir=/sources/xbpkg-audiofile-shared
cp -a "$SOURCE_DIR" "$shared_dir"

./configure --prefix=/usr
make -j"$JOBS"
make check

cd "$shared_dir"
./configure \
  --prefix=/usr \
  --disable-static
make -j"$JOBS"
make DESTDIR="$STAGE" install
