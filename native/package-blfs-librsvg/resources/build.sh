#!/usr/bin/env bash
set -euo pipefail

cp /sources/librsvg-2.62.3-Cargo.lock Cargo.lock
install -d vendor .cargo
tar --zstd -xf /sources/librsvg-2.62.3-crates.tar.zst -C /tmp

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

sed -e "/OUTDIR/s|,| / 'librsvg-2.62.3', '--no-namespace-dir',|" \
    -e '/output/s|Rsvg-2.0|librsvg-2.62.3|' \
    -i doc/meson.build

export CARGO_BUILD_JOBS="$JOBS"
meson setup build --prefix=/usr --buildtype=release --wrap-mode=nofallback
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
