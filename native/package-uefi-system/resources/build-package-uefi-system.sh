#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 7 ]]; then
  echo "usage: build-package-uefi-system.sh ROOTFS USER IMAGE EXTRA_MIB ESP_MIB SRC OUT" >&2
  exit 2
fi

rootfs_archive=$1
admin_user=$2
image_name=$3
extra_mib=$4
esp_mib=$5
source_root=$6
output_root=$7

if [[ ! "$admin_user" =~ ^[a-z_][a-z0-9_-]{0,31}$ ||
      ! "$image_name" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "invalid package UEFI identity" >&2
  exit 2
fi
for value_name in extra_mib esp_mib; do
  value=${!value_name}
  case "$value" in
    ''|*[!0-9]*)
      echo "$value_name must be a non-negative integer" >&2
      exit 2
      ;;
  esac
done
if ((esp_mib < 64)); then
  echo "ESP_MIB must be at least 64" >&2
  exit 2
fi
[[ -f "$rootfs_archive" && -f "$rootfs_archive.sha256" ]] || {
  echo "package rootfs artefact or checksum not found" >&2
  exit 1
}
(
  cd "$(dirname "$rootfs_archive")"
  sha256sum -c "$(basename "$rootfs_archive").sha256" >/dev/null
)

work_root="$source_root/package-uefi-system"
rootfs="$work_root/rootfs"
mount_dir="$work_root/mnt"
raw_image="$work_root/$image_name.raw"
output_dir="$output_root/opt/xbee-lfs-native"
loop_device=
esp_loop_device=
root_loop_device=

cleanup() {
  if mountpoint -q "$mount_dir/boot/efi"; then
    umount "$mount_dir/boot/efi"
  fi
  if mountpoint -q "$mount_dir"; then
    umount "$mount_dir"
  fi
  for device in "$root_loop_device" "$esp_loop_device" "$loop_device"; do
    if [[ -n "$device" ]]; then
      losetup --detach "$device" 2>/dev/null || true
    fi
  done
}
trap cleanup EXIT

rm -rf "$work_root"
mkdir -p "$rootfs" "$mount_dir" "$output_dir"
tar --zstd --xattrs --acls --numeric-owner \
  -xf "$rootfs_archive" -C "$rootfs"
chroot "$rootfs" id "$admin_user" >/dev/null
test "$(chroot "$rootfs" /usr/bin/xbpkg list | wc -l)" -eq 446

cat >"$rootfs/etc/fstab" <<'EOF'
/dev/vda2 / ext4 defaults 1 1
/dev/vda1 /boot/efi vfat umask=0077 0 1
EOF
mkdir -p "$rootfs/boot/efi"

uefi_rootfs="$output_dir/package-uefi-rootfs.tar.zst"
tar --xattrs --acls --numeric-owner --zstd \
  -C "$rootfs" -cf "$uefi_rootfs" .
(
  cd "$output_dir"
  sha256sum "$(basename "$uefi_rootfs")" \
    >"$(basename "$uefi_rootfs").sha256"
)

rootfs_mib=$(du -sm "$rootfs" | awk '{print $1}')
root_partition_mib=$((rootfs_mib + extra_mib))
if ((root_partition_mib < 4096)); then
  root_partition_mib=4096
fi
esp_end_mib=$((esp_mib + 1))
image_mib=$((esp_end_mib + root_partition_mib + 1))

truncate -s "${image_mib}M" "$raw_image"
parted --script "$raw_image" \
  mklabel gpt \
  mkpart ESP fat32 1MiB "${esp_end_mib}MiB" \
  set 1 esp on \
  mkpart root ext4 "${esp_end_mib}MiB" 100%

allocate_loop() {
  local candidate number
  candidate=$(losetup --find)
  if [[ ! -b "$candidate" ]]; then
    number=${candidate#/dev/loop}
    [[ "$number" =~ ^[0-9]+$ ]] || return 1
    mknod "$candidate" b 7 "$number"
  fi
  losetup "$@" "$candidate" "$raw_image"
  printf '%s\n' "$candidate"
}

loop_device=$(allocate_loop)
esp_loop_device=$(allocate_loop \
  --offset $((1024 * 1024)) \
  --sizelimit $((esp_mib * 1024 * 1024)))
root_loop_device=$(allocate_loop \
  --offset $((esp_end_mib * 1024 * 1024)) \
  --sizelimit $((root_partition_mib * 1024 * 1024)))

mkfs.vfat -F 32 -n XBEE_EFI "$esp_loop_device"
mkfs.ext4 -F -L xbee-lfs "$root_loop_device"
mount "$root_loop_device" "$mount_dir"
cp -a "$rootfs/." "$mount_dir/"
mount "$esp_loop_device" "$mount_dir/boot/efi"

/usr/sbin/grub-install \
  --target=x86_64-efi \
  --efi-directory="$mount_dir/boot/efi" \
  --boot-directory="$mount_dir/boot" \
  --modules="part_gpt fat ext2 normal linux" \
  --removable \
  --no-nvram \
  --recheck
cat >"$work_root/early-grub.cfg" <<'EOF'
if search --no-floppy --label xbee-lfs --set=root; then
    set prefix=($root)/boot/grub
    configfile ($root)/boot/grub/grub.cfg
else
    echo "XBee package root filesystem not found"
    halt
fi
EOF
/usr/bin/grub-mkstandalone \
  --format=x86_64-efi \
  --output="$mount_dir/boot/efi/EFI/BOOT/BOOTX64.EFI" \
  --modules="part_gpt fat ext2 search search_label normal configfile linux" \
  --locales="" \
  --fonts="" \
  "boot/grub/grub.cfg=$work_root/early-grub.cfg"
cat >"$mount_dir/boot/grub/grub.cfg" <<'EOF'
set default=0
set timeout=2

menuentry "XBee Linux From Scratch 13.0 (packages UEFI)" {
    linux /boot/vmlinuz-6.18.10-xbee-lfs root=/dev/vda2 ro console=tty0 console=ttyS0,115200n8
}
EOF

sync
umount "$mount_dir/boot/efi"
umount "$mount_dir"
losetup --detach "$root_loop_device"
root_loop_device=
losetup --detach "$esp_loop_device"
esp_loop_device=
losetup --detach "$loop_device"
loop_device=

qcow2="$output_dir/$image_name.qcow2"
qemu-img convert -f raw -O qcow2 -c "$raw_image" "$qcow2"
qemu-img check "$qcow2"
(
  cd "$output_dir"
  sha256sum "$(basename "$qcow2")" >"$(basename "$qcow2").sha256"
)

cat >"$output_dir/package-uefi-system-metadata.yaml" <<EOF
schema-version: 1
stage: package-uefi-system
repository-version: "0.34.1"
package-count: 446
architecture: x86_64
kernel: "6.18.10"
init: systemd
nocloud: xbee-nocloud
image:
  name: "$(basename "$qcow2")"
  format: qcow2
  firmware: uefi
  partition-table: gpt
  esp-size-mib: $esp_mib
  root-partition: 2
rootfs: "$(basename "$uefi_rootfs")"
EOF
