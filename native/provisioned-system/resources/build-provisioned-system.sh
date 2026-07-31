#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 9 ]]; then
  echo "usage: build-provisioned-system.sh ROOTFS SOURCES JOBS USER KEY_B64 IMAGE EXTRA_MIB SRC OUT" >&2
  exit 2
fi

rootfs_archive=$1
source_dir=$2
jobs=$3
admin_user=$4
authorized_key_base64=$5
image_name=$6
extra_mib=$7
source_root=$8
output_root=$9

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
if [[ ! "$admin_user" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
  echo "invalid administrator name: $admin_user" >&2
  exit 2
fi
if [[ ! "$image_name" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "invalid image name: $image_name" >&2
  exit 2
fi
if [[ "$(uname -m)" != "x86_64" ]]; then
  echo "the provisioned native builder supports x86_64 only" >&2
  exit 2
fi
if [[ ! -f "$rootfs_archive" || ! -f "$rootfs_archive.sha256" ]]; then
  echo "bootable rootfs artefact or checksum not found" >&2
  exit 1
fi
for source in sudo-1.9.17p2.tar.gz openssh-10.4p1.tar.gz SHA256SUMS; do
  if [[ ! -f "$source_dir/$source" ]]; then
    echo "verified provisioning source not found: $source" >&2
    exit 1
  fi
done

expected_checksum=$(awk 'NR == 1 {print $1}' "$rootfs_archive.sha256")
actual_checksum=$(sha256sum "$rootfs_archive" | awk '{print $1}')
if [[ -z "$expected_checksum" || "$actual_checksum" != "$expected_checksum" ]]; then
  echo "bootable rootfs checksum mismatch" >&2
  exit 1
fi
(cd "$source_dir" && sha256sum --check SHA256SUMS)

authorized_key=
if [[ -n "$authorized_key_base64" ]]; then
  if ! authorized_key=$(printf '%s' "$authorized_key_base64" | base64 --decode); then
    echo "access.authorized_key_base64 is not valid base64" >&2
    exit 2
  fi
  if [[ ! "$authorized_key" =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521))[[:space:]][A-Za-z0-9+/=]+([[:space:]].*)?$ ]]; then
    echo "decoded authorized key is not a supported OpenSSH public key" >&2
    exit 2
  fi
fi

work_root="$source_root/native-provisioned"
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
install -m 0644 "$source_dir/sudo-1.9.17p2.tar.gz" "$rootfs_dir/tmp/"
install -m 0644 "$source_dir/openssh-10.4p1.tar.gz" "$rootfs_dir/tmp/"

chroot "$rootfs_dir" /usr/bin/env -i \
  HOME=/root \
  TERM="${TERM:-dumb}" \
  PATH=/usr/bin:/usr/sbin \
  MAKEFLAGS="-j$jobs" \
  ADMIN_USER="$admin_user" \
  /bin/bash --noprofile --norc -s <<'CHROOT'
set -euo pipefail
cd /tmp

rm -rf sudo-1.9.17p2
tar -xf sudo-1.9.17p2.tar.gz
cd sudo-1.9.17p2
./configure \
  --prefix=/usr \
  --libexecdir=/usr/lib \
  --with-secure-path=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin \
  --with-env-editor \
  --without-pam \
  --without-sendmail
make
make install

cd /tmp
rm -rf openssh-10.4p1
tar -xf openssh-10.4p1.tar.gz
getent group sshd >/dev/null || groupadd --system sshd
id sshd >/dev/null 2>&1 || useradd --system --gid sshd --home-dir /var/lib/sshd --shell /bin/false sshd
install -d -m 0755 -o root -g root /var/lib/sshd
cd openssh-10.4p1
./configure \
  --prefix=/usr \
  --sysconfdir=/etc/ssh \
  --with-privsep-path=/var/lib/sshd \
  --with-pid-dir=/run \
  --with-default-path=/usr/local/bin:/usr/bin \
  --with-superuser-path=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin \
  --without-pam
make
make install

getent group "$ADMIN_USER" >/dev/null || groupadd "$ADMIN_USER"
if ! id "$ADMIN_USER" >/dev/null 2>&1; then
  useradd --create-home --gid "$ADMIN_USER" --shell /bin/bash "$ADMIN_USER"
fi
# "*" cannot match a password hash but, unlike the "!" lock marker, still
# permits OpenSSH public-key authentication. PasswordAuthentication is also
# disabled explicitly in sshd_config.
usermod --password '*' "$ADMIN_USER"

rm -rf /tmp/sudo-1.9.17p2 /tmp/openssh-10.4p1
rm -f /tmp/sudo-1.9.17p2.tar.gz /tmp/openssh-10.4p1.tar.gz
CHROOT

home_dir="$rootfs_dir/home/$admin_user"
install -d -m 0700 "$home_dir/.ssh"
if [[ -n "$authorized_key" ]]; then
  printf '%s\n' "$authorized_key" >"$home_dir/.ssh/authorized_keys"
else
  : >"$home_dir/.ssh/authorized_keys"
fi
chmod 0600 "$home_dir/.ssh/authorized_keys"
admin_uid=$(chroot "$rootfs_dir" id -u "$admin_user")
admin_gid=$(chroot "$rootfs_dir" id -g "$admin_user")
chown -R "$admin_uid:$admin_gid" "$home_dir"

cat >"$rootfs_dir/etc/sudoers.d/$admin_user" <<EOF
$admin_user ALL=(ALL:ALL) NOPASSWD: ALL
EOF
chmod 0440 "$rootfs_dir/etc/sudoers.d/$admin_user"

cat >"$rootfs_dir/etc/ssh/sshd_config" <<EOF
Port 22
AddressFamily any
ListenAddress 0.0.0.0
ListenAddress ::
HostKey /etc/ssh/ssh_host_ed25519_key
HostKey /etc/ssh/ssh_host_rsa_key
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no
AuthorizedKeysFile .ssh/authorized_keys
X11Forwarding no
AllowUsers $admin_user
Subsystem sftp internal-sftp
EOF

cat >"$rootfs_dir/usr/lib/systemd/system/sshd.service" <<'EOF'
[Unit]
Description=OpenSSH server daemon
After=network.target

[Service]
Type=simple
ExecStartPre=/usr/bin/ssh-keygen -A
ExecStart=/usr/sbin/sshd -D
ExecReload=/bin/kill -HUP $MAINPID
KillMode=process
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
ln -sfn /usr/lib/systemd/system/sshd.service \
  "$rootfs_dir/etc/systemd/system/multi-user.target.wants/sshd.service"

chroot "$rootfs_dir" /usr/sbin/visudo -cf "/etc/sudoers.d/$admin_user"
chroot "$rootfs_dir" /usr/bin/ssh-keygen -A
chroot "$rootfs_dir" /usr/sbin/sshd -t
rm -f "$rootfs_dir"/etc/ssh/ssh_host_*_key "$rootfs_dir"/etc/ssh/ssh_host_*_key.pub

for required in \
  "$rootfs_dir/usr/bin/sudo" \
  "$rootfs_dir/usr/sbin/sshd" \
  "$rootfs_dir/home/$admin_user/.ssh/authorized_keys"; do
  if [[ ! -e "$required" ]]; then
    echo "provisioned rootfs is missing: $required" >&2
    exit 1
  fi
done
if [[ ! -L "$rootfs_dir/etc/systemd/system/multi-user.target.wants/sshd.service" ]]; then
  echo "sshd.service is not enabled" >&2
  exit 1
fi

provisioned_archive="$output_dir/provisioned-rootfs.tar.zst"
tar --xattrs --acls --numeric-owner --zstd \
  -C "$rootfs_dir" -cf "$provisioned_archive" .
(
  cd "$output_dir"
  sha256sum "$(basename "$provisioned_archive")" >"$(basename "$provisioned_archive").sha256"
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

menuentry "XBee Linux From Scratch 13.0 (provisioned)" {
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

key_configured=false
if [[ -n "$authorized_key" ]]; then
  key_configured=true
fi
cat >"$output_dir/provisioned-metadata.yaml" <<EOF
schema-version: 1
lfs-book: "13.0"
stage: provisioned-system
architecture: x86_64
kernel: "6.18.10"
init: systemd
administrator: "$admin_user"
administrator-password: disabled
administrator-sudo: passwordless
ssh:
  server: "OpenSSH 10.4p1"
  public-key-configured: $key_configured
  password-authentication: false
  root-login: false
sudo: "1.9.17p2"
image:
  name: "$image_name"
  format: qcow2
  firmware: bios
  partition-table: msdos
  filesystem: ext4
  virtual-size-mib: $image_mib
artefacts:
  rootfs: provisioned-rootfs.tar.zst
  rootfs-checksum: provisioned-rootfs.tar.zst.sha256
  image: "$image_name.qcow2"
  image-checksum: "$image_name.qcow2.sha256"
EOF
