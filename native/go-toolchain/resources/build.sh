#!/usr/bin/env bash
set -euo pipefail

source_root=$1
output_root=$2
archive="$source_root/go1.26.2.linux-amd64.tar.gz"
destination="$output_root/opt/xbee-go"

rm -rf "$destination"
mkdir -p "$destination"
curl --fail --location --retry 3 --output "$archive" \
  https://go.dev/dl/go1.26.2.linux-amd64.tar.gz
printf '%s  %s\n' \
  '990e6b4bbba816dc3ee129eaeaf4b42f17c2800b88a2166c265ac1a200262282' \
  "$archive" | sha256sum --check --strict
tar -xzf "$archive" -C "$destination"
"$destination/go/bin/go" version
