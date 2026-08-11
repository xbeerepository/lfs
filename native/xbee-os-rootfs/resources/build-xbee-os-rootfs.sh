#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: build-xbee-os-rootfs.sh ROOTFS_ARCHIVE OUT" >&2
  exit 2
fi

rootfs_archive=$1
output_root=$2
checksum_file=$(dirname "$rootfs_archive")/SHA256SUMS

[[ -f "$rootfs_archive" && -f "$checksum_file" ]] || {
  echo "XBee OS rootfs or checksum not found" >&2
  exit 1
}
(
  cd "$(dirname "$rootfs_archive")"
  sha256sum --quiet -c SHA256SUMS
)

tar --zstd --numeric-owner -xf "$rootfs_archive" -C "$output_root"
mkdir -p "$output_root/workspace"
chmod 0755 "$output_root/workspace"

for executable in bin/bash usr/bin/env usr/bin/xbpkg; do
  [[ -x "$output_root/$executable" ]] || {
    echo "required executable missing from XBee OS: /$executable" >&2
    exit 1
  }
done
grep -Fxq ID=xbee-os "$output_root/etc/os-release"
