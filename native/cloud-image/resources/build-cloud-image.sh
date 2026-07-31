#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 7 ]]; then
  echo "usage: build-cloud-image.sh ROOTFS USER IMAGE EXTRA_MIB AGENT SRC OUT" >&2
  exit 2
fi

rootfs_archive=$1
admin_user=$2
image_name=$3
extra_mib=$4
agent=$5
source_root=$6
output_root=$7

case "$extra_mib" in
  ''|*[!0-9]*)
    echo "image.extra_size_mib must be a non-negative integer" >&2
    exit 2
    ;;
esac
if [[ ! "$admin_user" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
  echo "invalid administrator name: $admin_user" >&2
  exit 2
fi
if [[ ! "$image_name" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "invalid image name: $image_name" >&2
  exit 2
fi
if [[ ! -f "$rootfs_archive" || ! -f "$rootfs_archive.sha256" ]]; then
  echo "provisioned rootfs artefact or checksum not found" >&2
  exit 1
fi
if [[ ! -f "$agent" ]]; then
  echo "NoCloud agent not found" >&2
  exit 1
fi

expected_checksum=$(awk 'NR == 1 {print $1}' "$rootfs_archive.sha256")
actual_checksum=$(sha256sum "$rootfs_archive" | awk '{print $1}')
if [[ -z "$expected_checksum" || "$actual_checksum" != "$expected_checksum" ]]; then
  echo "provisioned rootfs checksum mismatch" >&2
  exit 1
fi

work_root="$source_root/native-cloud"
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

if ! chroot "$rootfs_dir" id "$admin_user" >/dev/null 2>&1; then
  echo "administrator is missing from provisioned rootfs: $admin_user" >&2
  exit 1
fi

# A cloud image must not contain a build-time identity or reusable host key.
: >"$rootfs_dir/home/$admin_user/.ssh/authorized_keys"
rm -f "$rootfs_dir"/etc/ssh/ssh_host_*_key "$rootfs_dir"/etc/ssh/ssh_host_*_key.pub
rm -rf "$rootfs_dir/var/lib/xbee-nocloud"

install -m 0755 "$agent" "$rootfs_dir/usr/sbin/xbee-nocloud"
cat >"$rootfs_dir/usr/lib/systemd/system/xbee-nocloud.service" <<EOF
[Unit]
Description=XBee minimal NoCloud first-boot provisioning
After=local-fs.target
Before=sshd.service

[Service]
Type=oneshot
Environment=XBEE_NOCLOUD_USER=$admin_user
ExecStart=/usr/sbin/xbee-nocloud
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
ln -sfn /usr/lib/systemd/system/xbee-nocloud.service \
  "$rootfs_dir/etc/systemd/system/multi-user.target.wants/xbee-nocloud.service"
mkdir -p "$rootfs_dir/etc/systemd/system/sshd.service.d"
cat >"$rootfs_dir/etc/systemd/system/sshd.service.d/nocloud.conf" <<'EOF'
[Unit]
Requires=xbee-nocloud.service
After=xbee-nocloud.service
EOF

cloud_archive="$output_dir/cloud-rootfs.tar.zst"
tar --xattrs --acls --numeric-owner --zstd \
  -C "$rootfs_dir" -cf "$cloud_archive" .
(
  cd "$output_dir"
  sha256sum "$(basename "$cloud_archive")" >"$(basename "$cloud_archive").sha256"
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
partition_loop_device=$(allocate_loop \
  --offset $((1024 * 1024)) \
  --sizelimit $(((image_mib - 1) * 1024 * 1024)))

mkfs.ext4 -F -L xbee-lfs "$partition_loop_device"
mount "$partition_loop_device" "$mount_dir"
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

menuentry "XBee Linux From Scratch 13.0 (cloud)" {
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

cat >"$output_dir/cloud-metadata.yaml" <<EOF
schema-version: 1
lfs-book: "13.0"
stage: cloud-image
architecture: x86_64
kernel: "6.18.10"
init: systemd
administrator: "$admin_user"
embedded-authorized-keys: false
nocloud:
  implementation: xbee-nocloud
  supported-metadata:
    - instance-id
    - local-hostname
    - public-keys
  supported-user-data:
    - hostname
    - ssh_authorized_keys
  arbitrary-user-data-execution: false
root-filesystem-auto-grow: true
image:
  name: "$image_name"
  format: qcow2
  firmware: bios
  partition-table: msdos
  filesystem: ext4
  virtual-size-mib: $image_mib
artefacts:
  rootfs: cloud-rootfs.tar.zst
  rootfs-checksum: cloud-rootfs.tar.zst.sha256
  image: "$image_name.qcow2"
  image-checksum: "$image_name.qcow2.sha256"
EOF
