#!/usr/bin/env bash
set -euo pipefail

cmake -S . -B build \
  -D CMAKE_INSTALL_PREFIX=/usr \
  -D CMAKE_BUILD_TYPE=Release \
  -D BUILD_SHARED_LIBS=ON
cmake --build build -j"$JOBS"

test_dir=$(mktemp -d)
faac -o "$test_dir/Front_Left.mp4" /usr/share/sounds/alsa/Front_Left.wav >/dev/null
./build/faad -o "$test_dir/Front_Left.wav" "$test_dir/Front_Left.mp4" >/dev/null
test -s "$test_dir/Front_Left.wav"
file "$test_dir/Front_Left.wav" | grep -Fq "WAVE audio"
rm -f "$test_dir/Front_Left.mp4" "$test_dir/Front_Left.wav"
rmdir "$test_dir"

DESTDIR="$STAGE" cmake --install build
