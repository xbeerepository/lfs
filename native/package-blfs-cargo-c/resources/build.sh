#!/usr/bin/env bash
set -euo pipefail

cp /sources/cargo-c-0.10.24-Cargo.lock Cargo.lock
install -d vendor .cargo
tar --zstd -xf /sources/cargo-c-0.10.24-crates.tar.zst -C /tmp

awk '
  /^\[\[package\]\]$/ {
    if (source ~ /^registry\+/) print checksum "\t" name "\t" version
    name = version = source = checksum = ""
    next
  }
  /^name = "/ {
    value = $0; sub(/^name = "/, "", value); sub(/"$/, "", value)
    name = value; next
  }
  /^version = "/ {
    value = $0; sub(/^version = "/, "", value); sub(/"$/, "", value)
    version = value; next
  }
  /^source = "/ {
    value = $0; sub(/^source = "/, "", value); sub(/"$/, "", value)
    source = value; next
  }
  /^checksum = "/ {
    value = $0; sub(/^checksum = "/, "", value); sub(/"$/, "", value)
    checksum = value; next
  }
  END {
    if (source ~ /^registry\+/) print checksum "\t" name "\t" version
  }
' Cargo.lock |
while IFS=$'\t' read -r checksum name version; do
  crate="/tmp/$name-$version.crate"
  directory="vendor/$name-$version"
  [[ -f "$crate" ]] || {
    echo "vendored crate not found: $name $version" >&2
    exit 1
  }
  tar -xf "$crate" -C vendor
  printf '{"files":{},"package":"%s"}\n' "$checksum" \
    >"$directory/.cargo-checksum.json"
done

cat >.cargo/config.toml <<'EOF'
[source.crates-io]
replace-with = "vendored-sources"

[source.vendored-sources]
directory = "vendor"

[net]
offline = true
EOF

export CARGO_BUILD_JOBS="$JOBS"
export LIBSSH2_SYS_USE_PKG_CONFIG=1
export LIBSQLITE3_SYS_USE_PKG_CONFIG=1

cargo build --release --offline --locked
install -Dm755 target/release/cargo-capi "$STAGE/usr/bin/cargo-capi"
install -Dm755 target/release/cargo-cbuild "$STAGE/usr/bin/cargo-cbuild"
install -Dm755 target/release/cargo-cinstall "$STAGE/usr/bin/cargo-cinstall"
install -Dm755 target/release/cargo-ctest "$STAGE/usr/bin/cargo-ctest"
install -Dm644 README.md \
  "$STAGE/usr/share/doc/cargo-c-$PACKAGE_VERSION/README.md"
