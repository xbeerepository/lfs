#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "usage: build-system-rootfs.sh ROOTFS XBPKG SRC OUT" >&2
  exit 2
fi

rootfs_archive=$1
package_manager=$2
source_root=$3
output_root=$4
checksum_file="$rootfs_archive.sha256"

if [[ ! -f "$rootfs_archive" || ! -f "$checksum_file" ]]; then
  echo "cloud rootfs artefact or checksum not found" >&2
  exit 1
fi
if [[ ! -x "$package_manager" || ! -f "$package_manager.sha256" ]]; then
  echo "xbpkg artefact or checksum not found" >&2
  exit 1
fi

expected=$(awk 'NR == 1 {print $1}' "$checksum_file")
actual=$(sha256sum "$rootfs_archive" | awk '{print $1}')
if [[ -z "$expected" || "$actual" != "$expected" ]]; then
  echo "cloud rootfs checksum mismatch" >&2
  exit 1
fi
expected=$(awk 'NR == 1 {print $1}' "$package_manager.sha256")
actual=$(sha256sum "$package_manager" | awk '{print $1}')
if [[ -z "$expected" || "$actual" != "$expected" ]]; then
  echo "xbpkg checksum mismatch" >&2
  exit 1
fi

mkdir -p "$source_root/system-rootfs-check"
tar --zstd --xattrs --acls --numeric-owner -xf "$rootfs_archive" -C "$output_root"

for executable in bin/bash usr/bin/env usr/bin/id usr/bin/getent; do
  if [[ ! -x "$output_root/$executable" ]]; then
    echo "required executable missing from system rootfs: /$executable" >&2
    exit 1
  fi
done
if ! chroot "$output_root" id xbee >/dev/null 2>&1; then
  echo "administrator xbee is missing from system rootfs" >&2
  exit 1
fi

# Containers need a fresh identity and must not inherit first-boot state.
: >"$output_root/etc/machine-id"
rm -f "$output_root/var/lib/dbus/machine-id"
rm -rf "$output_root/var/lib/xbee-nocloud"
# XBee bind-mounts its current runtime binary while executing a pack. Remove
# the empty build-time mount placeholder so the standalone OCI image does not
# expose a misleading /usr/bin/xbee.
rm -f "$output_root/usr/bin/xbee"
install -m 0755 "$package_manager" "$output_root/usr/bin/xbpkg"
mkdir -p "$output_root/workspace"
chmod 0755 "$output_root/workspace"
