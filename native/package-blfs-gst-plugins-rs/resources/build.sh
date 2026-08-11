#!/usr/bin/env bash
set -euo pipefail

export CARGO_BUILD_JOBS="$JOBS"
tar --zstd -xf "$(dirname "$0")/cargo-vendor-1.28.1.tar.zst"
cargo build --package gst-plugin-dav1d --release --locked --offline
cargo build --package gst-plugin-gtk4 --release --locked --offline

install -Dm755 target/release/libgstdav1d.so \
  "$STAGE/usr/lib/gstreamer-1.0/libgstdav1d.so"
install -Dm755 target/release/libgstgtk4.so \
  "$STAGE/usr/lib/gstreamer-1.0/libgstgtk4.so"
