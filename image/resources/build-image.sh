#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 5 ]]; then
  echo "usage: build-image.sh ROOTFS_ARCHIVE IMAGE_NAME EXTRA_MIB SRC OUT" >&2
  exit 2
fi

rootfs_archive=$1
image_name=$2
extra_mib=$3
source_root=$4
output_root=$5

case "$extra_mib" in
  ''|*[!0-9]*)
    echo "image.extra-size-mib must be a non-negative integer" >&2
    exit 2
    ;;
esac

if [[ ! -f "$rootfs_archive" ]]; then
  echo "rootfs artefact not found: $rootfs_archive" >&2
  exit 1
fi

work_root="$source_root/image-work"
rootfs_dir="$work_root/rootfs"
mount_dir="$work_root/mnt"
raw_image="$work_root/$image_name.raw"
output_dir="$output_root/opt/xbee-lfs"
loop_device=

cleanup() {
  if mountpoint -q "$mount_dir"; then
    umount "$mount_dir"
  fi
  if [[ -n "$loop_device" ]]; then
    losetup --detach "$loop_device" 2>/dev/null || true
  fi
}
trap cleanup EXIT

mkdir -p "$rootfs_dir" "$mount_dir" "$output_dir"
tar --zstd --xattrs --acls --numeric-owner -xf "$rootfs_archive" -C "$rootfs_dir"

rootfs_mib=$(du -sm "$rootfs_dir" | awk '{print $1}')
image_mib=$((rootfs_mib + extra_mib))
if (( image_mib < 4096 )); then
  image_mib=4096
fi

truncate -s "${image_mib}M" "$raw_image"
parted --script "$raw_image" \
  mklabel msdos \
  mkpart primary ext4 1MiB 100% \
  set 1 boot on

loop_device=$(losetup --find --show --partscan "$raw_image")
partition="${loop_device}p1"
for _ in {1..20}; do
  [[ -b "$partition" ]] && break
  sleep 0.1
done
if [[ ! -b "$partition" ]]; then
  echo "partition device was not created for $loop_device" >&2
  exit 1
fi

mkfs.ext4 -F -L xbee-lfs "$partition"
mount "$partition" "$mount_dir"
cp -a "$rootfs_dir/." "$mount_dir/"

grub-install \
  --target=i386-pc \
  --boot-directory="$mount_dir/boot" \
  --modules="part_msdos ext2 normal linux" \
  "$loop_device"

kernel=$(find "$mount_dir/boot" -maxdepth 1 -type f -name 'vmlinuz-*' \
  -printf '%f\n' | sort -V | tail -n 1)
if [[ -z "$kernel" ]]; then
  echo "no kernel found in the generated root filesystem" >&2
  exit 1
fi

mkdir -p "$mount_dir/boot/grub"
cat >"$mount_dir/boot/grub/grub.cfg" <<EOF
set default=0
set timeout=2

menuentry "XBee Linux From Scratch" {
    linux /boot/$kernel root=/dev/vda1 ro console=ttyS0
}
EOF

sync
umount "$mount_dir"
losetup --detach "$loop_device"
loop_device=

qcow2="$output_dir/$image_name.qcow2"
qemu-img convert -f raw -O qcow2 -c "$raw_image" "$qcow2"
qemu-img check "$qcow2"
sha256sum "$qcow2" >"$qcow2.sha256"

cat >"$output_dir/image-metadata.yaml" <<EOF
schema-version: 1
image:
  name: "$image_name"
  format: qcow2
  architecture: x86_64
  firmware: bios
  partition-table: msdos
  filesystem: ext4
  virtual-size-mib: $image_mib
artefacts:
  image: "$image_name.qcow2"
  checksum: "$image_name.qcow2.sha256"
EOF

