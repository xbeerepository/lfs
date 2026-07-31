#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 8 ]]; then
  echo "usage: build-release-system.sh BIOS BIOS_META UEFI UEFI_META NAME RESOURCES SRC OUT" >&2
  exit 2
fi

bios_image=$1
bios_metadata=$2
uefi_image=$3
uefi_metadata=$4
release_name=$5
resources=$6
source_root=$7
output_root=$8

if [[ ! "$release_name" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "invalid release name: $release_name" >&2
  exit 2
fi

verify_artefact() {
  local artefact=$1
  local checksum_file="$artefact.sha256"
  local expected actual

  if [[ ! -f "$artefact" || ! -f "$checksum_file" ]]; then
    echo "artefact or checksum not found: $artefact" >&2
    exit 1
  fi
  expected=$(awk 'NR == 1 {print $1}' "$checksum_file")
  actual=$(sha256sum "$artefact" | awk '{print $1}')
  if [[ -z "$expected" || "$actual" != "$expected" ]]; then
    echo "checksum mismatch: $artefact" >&2
    exit 1
  fi
}

verify_artefact "$bios_image"
verify_artefact "$uefi_image"
for metadata in "$bios_metadata" "$uefi_metadata"; do
  if [[ ! -s "$metadata" ]]; then
    echo "metadata not found: $metadata" >&2
    exit 1
  fi
done
for resource in README.release.md meta-data user-data; do
  if [[ ! -f "$resources/$resource" ]]; then
    echo "release resource not found: $resource" >&2
    exit 1
  fi
done

work_root="$source_root/native-release"
release_dir="$work_root/$release_name"
output_dir="$output_root/opt/xbee-lfs-native"
archive="$output_dir/$release_name-release.tar.zst"
virtualbox_image="$output_dir/$release_name-virtualbox.vmdk"

rm -rf "$work_root"
mkdir -p \
  "$release_dir/images" \
  "$release_dir/metadata" \
  "$release_dir/nocloud-seed" \
  "$output_dir"

install -m 0644 "$bios_image" "$release_dir/images/"
install -m 0644 "$uefi_image" "$release_dir/images/"
qemu-img convert -f qcow2 -O vmdk \
  "$bios_image" \
  "$virtualbox_image"
install -m 0644 "$virtualbox_image" "$release_dir/images/"
install -m 0644 "$bios_metadata" "$release_dir/metadata/"
install -m 0644 "$uefi_metadata" "$release_dir/metadata/"
install -m 0644 "$resources/README.release.md" "$release_dir/README.md"
install -m 0644 "$resources/meta-data" "$release_dir/nocloud-seed/meta-data"
install -m 0644 "$resources/user-data" "$release_dir/nocloud-seed/user-data"

(
  cd "$release_dir"
  sha256sum images/*.qcow2 images/*.vmdk metadata/*.yaml >SHA256SUMS
)

cat >"$release_dir/release.yaml" <<EOF
schema-version: 1
name: "$release_name"
lfs-book: "13.0"
architecture: x86_64
kernel: "6.18.10"
images:
  bios:
    file: images/$(basename "$bios_image")
    firmware: bios
    partition-table: msdos
  uefi:
    file: images/$(basename "$uefi_image")
    firmware: uefi
    partition-table: gpt
  virtualbox:
    file: images/${release_name}-virtualbox.vmdk
    firmware: bios
    source: bios
nocloud-seed-template: nocloud-seed
checksums: SHA256SUMS
EOF

tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner \
  --zstd -C "$work_root" -cf "$archive" "$release_name"
(
  cd "$output_dir"
  sha256sum "$(basename "$virtualbox_image")" \
    >"$(basename "$virtualbox_image").sha256"
  sha256sum "$(basename "$archive")" >"$(basename "$archive").sha256"
)

cat >"$output_dir/release-metadata.yaml" <<EOF
schema-version: 1
stage: release-system
name: "$release_name"
format: tar.zst
archive: "$(basename "$archive")"
archive-checksum: "$(basename "$archive").sha256"
virtualbox-image: "$(basename "$virtualbox_image")"
virtualbox-image-checksum: "$(basename "$virtualbox_image").sha256"
contains:
  - bios-qcow2
  - uefi-qcow2
  - virtualbox-vmdk
  - nocloud-seed-template
  - sha256-manifest
EOF
