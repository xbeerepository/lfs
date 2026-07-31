#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 10 ]]; then
  echo "usage: build-bootable-system.sh ROOTFS SOURCES JOBS HOSTNAME LOCALE IMAGE EXTRA_MIB KCONFIG SRC OUT" >&2
  exit 2
fi

rootfs_archive=$1
source_dir=$2
jobs=$3
lfs_hostname=$4
lfs_locale=$5
image_name=$6
extra_mib=$7
kernel_fragment=$8
source_root=$9
output_root=${10}

case "$jobs" in
  ''|*[!0-9]*|0)
    echo "lfs.jobs must be a positive integer" >&2
    exit 2
    ;;
esac
case "$extra_mib" in
  ''|*[!0-9]*)
    echo "image.extra_size_mib must be a non-negative integer" >&2
    exit 2
    ;;
esac
if [[ ! "$lfs_hostname" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*$ ]]; then
  echo "invalid hostname: $lfs_hostname" >&2
  exit 2
fi
if [[ ! "$lfs_locale" =~ ^[A-Za-z0-9_.@-]+$ ]]; then
  echo "invalid locale: $lfs_locale" >&2
  exit 2
fi
if [[ ! "$image_name" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "invalid image name: $image_name" >&2
  exit 2
fi
if [[ "$(uname -m)" != "x86_64" ]]; then
  echo "the bootable native builder supports x86_64 only" >&2
  exit 2
fi
if [[ ! -f "$rootfs_archive" || ! -f "$rootfs_archive.sha256" ]]; then
  echo "final rootfs artefact or checksum not found" >&2
  exit 1
fi
if [[ ! -f "$source_dir/linux-6.18.10.tar.xz" || ! -f "$source_dir/MD5SUMS" ]]; then
  echo "verified Linux source artefact not found" >&2
  exit 1
fi
if [[ ! -f "$kernel_fragment" ]]; then
  echo "kernel configuration fragment not found" >&2
  exit 1
fi

expected_checksum=$(awk 'NR == 1 {print $1}' "$rootfs_archive.sha256")
actual_checksum=$(sha256sum "$rootfs_archive" | awk '{print $1}')
if [[ -z "$expected_checksum" || "$actual_checksum" != "$expected_checksum" ]]; then
  echo "final rootfs checksum mismatch" >&2
  exit 1
fi
(cd "$source_dir" && md5sum --check MD5SUMS)

work_root="$source_root/native-bootable"
rootfs_dir="$work_root/rootfs"
mount_dir="$work_root/mnt"
raw_image="$work_root/$image_name.raw"
output_dir="$output_root/opt/xbee-lfs-native"
loop_device=
partition_loop_device=

cleanup() {
  if mountpoint -q "$mount_dir"; then
    umount "$mount_dir"
  fi
  if [[ -n "$partition_loop_device" ]]; then
    losetup --detach "$partition_loop_device" 2>/dev/null || true
  fi
  if [[ -n "$loop_device" ]]; then
    losetup --detach "$loop_device" 2>/dev/null || true
  fi
}
trap cleanup EXIT

rm -rf "$work_root"
mkdir -p "$rootfs_dir" "$mount_dir" "$output_dir"
tar --zstd --xattrs --acls --numeric-owner -xf "$rootfs_archive" -C "$rootfs_dir"

install -m 0644 "$source_dir/linux-6.18.10.tar.xz" "$rootfs_dir/tmp/"
install -m 0644 "$kernel_fragment" "$rootfs_dir/tmp/kernel-x86_64.config"

cat >"$rootfs_dir/etc/fstab" <<'EOF'
# file system  mount-point  type  options             dump  fsck
/dev/vda1      /            ext4  defaults            1     1
proc           /proc        proc  nosuid,noexec,nodev 0     0
sysfs          /sys         sysfs nosuid,noexec,nodev 0     0
devpts         /dev/pts     devpts gid=5,mode=620     0     0
tmpfs          /run         tmpfs defaults            0     0
tmpfs          /tmp         tmpfs mode=1777           0     0
EOF

printf '%s\n' "$lfs_hostname" >"$rootfs_dir/etc/hostname"
cat >"$rootfs_dir/etc/hosts" <<EOF
127.0.0.1 localhost
127.0.1.1 $lfs_hostname
::1       localhost ip6-localhost ip6-loopback
EOF
printf 'LANG=%s\n' "$lfs_locale" >"$rootfs_dir/etc/locale.conf"
printf '%s\n' 'KEYMAP=us' >"$rootfs_dir/etc/vconsole.conf"

mkdir -p "$rootfs_dir/etc/systemd/network"
cat >"$rootfs_dir/etc/systemd/network/20-wired.network" <<'EOF'
[Match]
Name=en* eth*

[Network]
DHCP=yes
EOF
ln -sfn /run/systemd/resolve/stub-resolv.conf "$rootfs_dir/etc/resolv.conf"

cat >"$rootfs_dir/etc/os-release" <<'EOF'
NAME="XBee Linux From Scratch"
ID=xbee-lfs
VERSION="13.0"
VERSION_ID="13.0"
PRETTY_NAME="XBee Linux From Scratch 13.0"
HOME_URL="https://www.linuxfromscratch.org/"
EOF
ln -sfn ../os-release "$rootfs_dir/usr/lib/os-release"

mkdir -p "$rootfs_dir/etc/systemd/system/multi-user.target.wants"
ln -sfn /usr/lib/systemd/system/systemd-networkd.service \
  "$rootfs_dir/etc/systemd/system/multi-user.target.wants/systemd-networkd.service"
ln -sfn /usr/lib/systemd/system/systemd-resolved.service \
  "$rootfs_dir/etc/systemd/system/multi-user.target.wants/systemd-resolved.service"
ln -sfn /usr/lib/systemd/system/multi-user.target \
  "$rootfs_dir/etc/systemd/system/default.target"
: >"$rootfs_dir/etc/machine-id"

chroot "$rootfs_dir" /usr/bin/env -i \
  HOME=/root \
  TERM="${TERM:-dumb}" \
  PATH=/usr/bin:/usr/sbin \
  MAKEFLAGS="-j$jobs" \
  LFS_JOBS="$jobs" \
  /bin/bash --noprofile --norc -s <<'CHROOT'
set -euo pipefail
cd /tmp
rm -rf linux-6.18.10
tar -xf linux-6.18.10.tar.xz
cd linux-6.18.10
make mrproper
make defconfig
scripts/kconfig/merge_config.sh -m .config /tmp/kernel-x86_64.config
make olddefconfig
make
make modules_install
install -m 0644 arch/x86/boot/bzImage /boot/vmlinuz-6.18.10-xbee-lfs
install -m 0644 System.map /boot/System.map-6.18.10-xbee-lfs
install -m 0644 .config /boot/config-6.18.10-xbee-lfs
rm -f /lib/modules/6.18.10/build /lib/modules/6.18.10/source
cd /tmp
rm -rf linux-6.18.10 linux-6.18.10.tar.xz kernel-x86_64.config
CHROOT

for required in \
  "$rootfs_dir/boot/vmlinuz-6.18.10-xbee-lfs" \
  "$rootfs_dir/usr/lib/systemd/systemd" \
  "$rootfs_dir/etc/fstab" \
  "$rootfs_dir/etc/systemd/network/20-wired.network"; do
  if [[ ! -e "$required" ]]; then
    echo "bootable rootfs is missing: $required" >&2
    exit 1
  fi
done

configured_archive="$output_dir/bootable-rootfs.tar.zst"
tar --xattrs --acls --numeric-owner --zstd \
  --exclude='./sources' \
  -C "$rootfs_dir" -cf "$configured_archive" .
(
  cd "$output_dir"
  sha256sum "$(basename "$configured_archive")" >"$(basename "$configured_archive").sha256"
)

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

allocate_loop() {
  local candidate number
  candidate=$(losetup --find)
  if [[ ! -b "$candidate" ]]; then
    number=${candidate#/dev/loop}
    [[ "$number" =~ ^[0-9]+$ ]] || {
      echo "unexpected loop device name: $candidate" >&2
      return 1
    }
    mknod "$candidate" b 7 "$number"
  fi
  losetup "$@" "$candidate" "$raw_image"
  printf '%s\n' "$candidate"
}

loop_device=$(allocate_loop)
# Map the filesystem region explicitly. This avoids relying on udev to create
# /dev/loopXp1, which is not available in XBee's minimal build container.
partition_loop_device=$(allocate_loop \
  --offset $((1024 * 1024)) \
  --sizelimit $(((image_mib - 1) * 1024 * 1024)))
partition="$partition_loop_device"

mkfs.ext4 -F -L xbee-lfs "$partition"
mount "$partition" "$mount_dir"
cp -a "$rootfs_dir/." "$mount_dir/"

/usr/sbin/grub-install \
  --target=i386-pc \
  --boot-directory="$mount_dir/boot" \
  --modules="biosdisk part_msdos ext2 normal linux" \
  --recheck \
  "$loop_device"

cat >"$mount_dir/boot/grub/grub.cfg" <<'EOF'
set default=0
set timeout=2

menuentry "XBee Linux From Scratch 13.0" {
    linux /boot/vmlinuz-6.18.10-xbee-lfs root=/dev/vda1 ro console=tty0 console=ttyS0,115200n8
}
EOF

sync
umount "$mount_dir"
losetup --detach "$partition_loop_device"
partition_loop_device=
losetup --detach "$loop_device"
loop_device=

qcow2="$output_dir/$image_name.qcow2"
qemu-img convert -f raw -O qcow2 -c "$raw_image" "$qcow2"
qemu-img check "$qcow2"
(
  cd "$output_dir"
  sha256sum "$(basename "$qcow2")" >"$(basename "$qcow2").sha256"
)

cat >"$output_dir/bootable-metadata.yaml" <<EOF
schema-version: 1
lfs-book: "13.0"
stage: bootable-system
architecture: x86_64
kernel: "6.18.10"
init: systemd
hostname: "$lfs_hostname"
locale: "$lfs_locale"
root-account: locked
image:
  name: "$image_name"
  format: qcow2
  firmware: bios
  partition-table: msdos
  filesystem: ext4
  virtual-size-mib: $image_mib
artefacts:
  rootfs: bootable-rootfs.tar.zst
  rootfs-checksum: bootable-rootfs.tar.zst.sha256
  image: "$image_name.qcow2"
  image-checksum: "$image_name.qcow2.sha256"
EOF
