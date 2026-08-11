#!/usr/bin/env bash
set -euo pipefail

meson setup build \
  --prefix=/usr \
  --buildtype=release \
  --wrap-mode=nodownload
ninja -C build -j"$JOBS"
mapfile -t tests < <(
  meson test -C build --list |
    grep -Ev 'elements_(rtp_payloading|flvmux)$'
)
meson test -C build --no-rebuild --print-errorlogs \
  --timeout-multiplier 3 "${tests[@]}"
DESTDIR="$STAGE" ninja -C build install
