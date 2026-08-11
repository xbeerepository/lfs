#!/usr/bin/env bash
set -euo pipefail

install -d build/cache/2026-05-28
for component in rustc rust-std cargo; do
  install -m644 \
    "/sources/$component-1.96.0-x86_64-unknown-linux-gnu.tar.xz" \
    build/cache/2026-05-28/
done

cat >bootstrap.toml <<'EOF'
change-id = 154587

[llvm]
targets = "X86"

[build]
description = "for XBee LFS"
docs = false
tools = ["cargo", "rustdoc"]

[install]
prefix = "/usr"
docdir = "share/doc/rustc-1.97.1"

[rust]
channel = "stable"
lto = "thin"
codegen-units = 1
llvm-bitcode-linker = false
EOF

export CARGO_BUILD_JOBS="$JOBS"
export LIBSSH2_SYS_USE_PKG_CONFIG=1
export LIBSQLITE3_SYS_USE_PKG_CONFIG=1

./x.py build --jobs "$JOBS"
DESTDIR="$STAGE" ./x.py install --jobs "$JOBS"

install -Dm644 README.md \
  "$STAGE/usr/share/doc/rustc-$PACKAGE_VERSION/README.md"
