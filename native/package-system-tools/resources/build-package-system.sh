#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 10 ]]; then
  echo "usage: build-package-system.sh REPOSITORY USER HOSTNAME AUTHORIZED_KEY IMAGE EXTRA_MIB NOCLOUD_AGENT PROFILE SRC OUT" >&2
  exit 2
fi

repository=$1
admin_user=$2
lfs_hostname=$3
authorized_key=$4
image_name=$5
extra_mib=$6
nocloud_agent=$7
profile_file=$8
source_root=$9
output_root=${10}
profile=$(basename "$profile_file" .txt)
desktop_profile=false
if [[ "$profile" == full || "$profile" == desktop-sway ]]; then
  desktop_profile=true
fi

if [[ ! "$admin_user" =~ ^[a-z_][a-z0-9_-]{0,31}$ ||
      ! "$lfs_hostname" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ||
      ! "$image_name" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "invalid package-system identity" >&2
  exit 2
fi
case "$extra_mib" in
  ''|*[!0-9]*)
    echo "EXTRA_MIB must be a non-negative integer" >&2
    exit 2
    ;;
esac
if [[ -n "$authorized_key" ]] &&
   [[ ! "$authorized_key" =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521))[[:space:]][A-Za-z0-9+/=]+([[:space:]].*)?$ ]]; then
  echo "invalid SSH authorized key" >&2
  exit 2
fi
[[ -f "$nocloud_agent" ]] || {
  echo "NoCloud agent not found: $nocloud_agent" >&2
  exit 1
}
[[ -f "$profile_file" && "$profile" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || {
  echo "invalid package profile: $profile_file" >&2
  exit 1
}

manager="$repository/bin/xbpkg"
packages="$repository/packages"
[[ -x "$manager" && -d "$packages" &&
   -f "$repository/SHA256SUMS" &&
   -f "$repository/SHA256SUMS.sig" &&
   -f "$repository/SHA256SUMS.keyid" &&
   -f "$repository/repository-ed25519-public.pem" ]] || {
  echo "package repository is incomplete" >&2
  exit 1
}
repository_key_id=$(head -n 1 "$repository/SHA256SUMS.keyid")
actual_key_id=$(openssl pkey -pubin \
  -in "$repository/repository-ed25519-public.pem" -outform DER |
  sha256sum | awk '{print $1}')
[[ "$repository_key_id" =~ ^[[:xdigit:]]{64}$ &&
   "$repository_key_id" == "$actual_key_id" ]] || {
  echo "repository signing key identifier mismatch" >&2
  exit 1
}
openssl pkeyutl -verify -pubin \
  -inkey "$repository/repository-ed25519-public.pem" \
  -sigfile "$repository/SHA256SUMS.sig" -rawin \
  -in "$repository/SHA256SUMS" >/dev/null
(cd "$repository" && sha256sum -c SHA256SUMS >/dev/null)

work_root="$source_root/package-system-$profile"
rootfs="$work_root/rootfs"
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
mkdir -p "$rootfs" "$mount_dir" "$output_dir"

while IFS= read -r name; do
  name=${name%%#*}
  name=${name//[[:space:]]/}
  [[ -n "$name" ]] || continue
  [[ "$name" =~ ^[a-z0-9][a-z0-9+._-]*$ ]] || {
    echo "invalid package in profile $profile: $name" >&2
    exit 1
  }
  "$manager" --root "$rootfs" --repository "$repository" \
    --trusted-key "$repository/repository-ed25519-public.pem" install "$name"
done <"$profile_file"
package_count=$("$manager" --root "$rootfs" list | wc -l)
((package_count > 0))
if [[ "$profile" == full && "$package_count" -ne 446 ]]; then
  echo "full profile must install 446 packages, got $package_count" >&2
  exit 1
fi
if [[ "$profile" == minimal ]]; then
  for required in bash coreutils systemd openssh dhcpcd wget linux-kernel linux-modules; do
    "$manager" --root "$rootfs" list | awk '{print $1}' | grep -Fxq "$required" || {
      echo "minimal profile is missing required package: $required" >&2
      exit 1
    }
  done
  for excluded in curl gcc; do
    if "$manager" --root "$rootfs" list | awk '{print $1}' | grep -Fxq "$excluded"; then
      echo "minimal profile unexpectedly contains: $excluded" >&2
      exit 1
    fi
  done
fi
install -m 0755 "$manager" "$rootfs/usr/bin/xbpkg"

mkdir -p \
  "$rootfs/dev/pts" "$rootfs/proc" "$rootfs/sys" "$rootfs/run" "$rootfs/tmp" \
  "$rootfs/boot" "$rootfs/home/$admin_user/.ssh" "$rootfs/root" \
  "$rootfs/etc/systemd/system/multi-user.target.wants" \
  "$rootfs/etc/systemd/system/sockets.target.wants" \
  "$rootfs/etc/sudoers.d" "$rootfs/etc/xbpkg/trusted-keys" \
  "$rootfs/var/lib/sshd" "$rootfs/var/log"
install -m 0644 "$repository/repository-ed25519-public.pem" \
  "$rootfs/etc/xbpkg/trusted-repository-key.pem"
install -m 0644 "$repository/repository-ed25519-public.pem" \
  "$rootfs/etc/xbpkg/trusted-keys/$repository_key_id.pem"
: >"$rootfs/etc/xbpkg/revoked-keys"
chmod 1777 "$rootfs/tmp"
chmod 0700 "$rootfs/root" "$rootfs/home/$admin_user/.ssh"
[[ -e "$rootfs/dev/null" ]] || mknod -m 0666 "$rootfs/dev/null" c 1 3
[[ -e "$rootfs/dev/zero" ]] || mknod -m 0666 "$rootfs/dev/zero" c 1 5
[[ -e "$rootfs/dev/random" ]] || mknod -m 0666 "$rootfs/dev/random" c 1 8
[[ -e "$rootfs/dev/urandom" ]] || mknod -m 0666 "$rootfs/dev/urandom" c 1 9
[[ -e "$rootfs/dev/tty" ]] || mknod -m 0666 "$rootfs/dev/tty" c 5 0
[[ -e "$rootfs/dev/console" ]] || mknod -m 0600 "$rootfs/dev/console" c 5 1

for legacy_dir in bin sbin lib lib64; do
  if [[ -d "$rootfs/$legacy_dir" && ! -L "$rootfs/$legacy_dir" ]]; then
    rmdir "$rootfs/$legacy_dir" 2>/dev/null || true
  fi
done
[[ -e "$rootfs/bin" || -L "$rootfs/bin" ]] ||
  ln -s usr/bin "$rootfs/bin"
[[ -e "$rootfs/sbin" || -L "$rootfs/sbin" ]] ||
  ln -s usr/sbin "$rootfs/sbin"
[[ -e "$rootfs/lib" || -L "$rootfs/lib" ]] ||
  ln -s usr/lib "$rootfs/lib"
[[ -e "$rootfs/lib64" || -L "$rootfs/lib64" ]] ||
  ln -s usr/lib64 "$rootfs/lib64"
ln -sfn bash "$rootfs/usr/bin/sh"

cat >"$rootfs/etc/passwd" <<EOF
root:x:0:0:root:/root:/bin/bash
bin:x:1:1:bin:/dev/null:/bin/false
daemon:x:6:6:Daemon User:/dev/null:/bin/false
messagebus:x:18:18:D-Bus Message Daemon User:/run/dbus:/bin/false
systemd-network:x:192:192:systemd Network Management:/:/bin/false
systemd-oom:x:195:195:systemd Userspace OOM Killer:/:/bin/false
systemd-resolve:x:193:193:systemd Resolver:/:/bin/false
systemd-timesync:x:194:194:systemd Time Synchronization:/:/bin/false
polkitd:x:102:102:PolicyKit Daemon:/var/lib/polkit-1:/bin/false
nobody:x:65534:65534:Unprivileged User:/dev/null:/bin/false
$admin_user:x:1000:1000:XBee Administrator:/home/$admin_user:/bin/bash
EOF
cat >"$rootfs/etc/group" <<EOF
root:x:0:
bin:x:1:
daemon:x:6:
tty:x:5:
disk:x:8:
kmem:x:9:
wheel:x:10:$admin_user
audio:x:11:$admin_user
video:x:12:$admin_user
utmp:x:13:
messagebus:x:18:
polkitd:x:102:
cdrom:x:20:$admin_user
clock:x:21:
input:x:24:$admin_user
tape:x:26:
dialout:x:27:$admin_user
lp:x:28:
kvm:x:61:$admin_user
netdev:x:86:$admin_user
systemd-journal:x:190:
systemd-network:x:192:
systemd-resolve:x:193:
systemd-timesync:x:194:
systemd-oom:x:195:
users:x:999:
$admin_user:x:1000:
nogroup:x:65534:
EOF
cat >"$rootfs/etc/shadow" <<EOF
root:!:1::::::
bin:!:1::::::
daemon:!:1::::::
messagebus:!:1::::::
systemd-network:!:1::::::
systemd-resolve:!:1::::::
systemd-timesync:!:1::::::
systemd-oom:!:1::::::
polkitd:!:1::::::
nobody:!:1::::::
$admin_user:NP:1::::::
EOF
chmod 0644 "$rootfs/etc/passwd" "$rootfs/etc/group"
chmod 0400 "$rootfs/etc/shadow"
if [[ "$desktop_profile" == true ]]; then
  mkdir -p "$rootfs/home/$admin_user/.config/sway"
  cat >"$rootfs/home/$admin_user/.config/sway/config" <<'EOF'
include /etc/sway/config

# Start the freedesktop.org notification daemon with the Sway session.
exec dunst

# Lock after five minutes when a password has been provisioned, blank the
# displays after ten minutes, and lock before system sleep.
exec /usr/bin/xbee-swayidle

# Present graphical privilege prompts inside the Wayland session.
exec /usr/libexec/polkit-gnome-authentication-agent-1
EOF
  cat >"$rootfs/usr/bin/xbee-swayidle" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if passwd -S "$USER" | awk '$2 == "P" { found=1 } END { exit !found }'; then
  exec swayidle -w \
    timeout 300 'swaylock -f -c 000000' \
    timeout 600 'swaymsg "output * power off"' \
    resume 'swaymsg "output * power on"' \
    before-sleep 'swaylock -f -c 000000'
fi

exec swayidle -w \
  timeout 600 'swaymsg "output * power off"' \
  resume 'swaymsg "output * power on"'
EOF
  chmod 0755 "$rootfs/usr/bin/xbee-swayidle"
  [[ -x "$rootfs/usr/bin/dunst" &&
     -x "$rootfs/usr/bin/notify-send" &&
     -x "$rootfs/usr/bin/swayidle" &&
     -x "$rootfs/usr/bin/swaylock" &&
     -x "$rootfs/usr/bin/pkexec" &&
     -x "$rootfs/usr/lib/polkit-1/polkitd" &&
     -x "$rootfs/usr/libexec/accounts-daemon" &&
     -x "$rootfs/usr/libexec/polkit-gnome-authentication-agent-1" &&
     -x "$rootfs/usr/sbin/NetworkManager" &&
     -x "$rootfs/usr/bin/nmcli" &&
     -x "$rootfs/usr/sbin/wpa_supplicant" &&
     -f "$rootfs/etc/pam.d/polkit-1" &&
     -f "$rootfs/usr/lib/systemd/system/NetworkManager.service" &&
     -f "$rootfs/usr/lib/systemd/system/polkit.service" &&
     -f "$rootfs/usr/lib/systemd/system/accounts-daemon.service" &&
     -f "$rootfs/etc/pam.d/swaylock" &&
     -f "$rootfs/usr/share/dbus-1/services/org.knopwob.dunst.service" &&
     -f "$rootfs/usr/lib/systemd/user/dunst.service" ]] || {
    echo "$profile profile desktop service stack is incomplete" >&2
    exit 1
  }
  install -d -m 0750 -o 0 -g 102 "$rootfs/etc/polkit-1/rules.d"
  install -d -m 0755 "$rootfs/etc/systemd/system/NetworkManager.service.d"
  cat >"$rootfs/etc/systemd/system/NetworkManager.service.d/xbee-dbus.conf" <<'EOF'
[Service]
# The image uses dbus-daemon without socket activation. Avoid systemd's
# implicit dbus.socket dependency while keeping NetworkManager on D-Bus.
Type=simple
BusName=
EOF
  cat >"$rootfs/etc/polkit-1/rules.d/50-networkmanager.rules" <<'EOF'
polkit.addRule(function(action, subject) {
    if (action.id.indexOf("org.freedesktop.NetworkManager.") == 0 &&
        subject.isInGroup("netdev")) {
        return polkit.Result.YES;
    }
});
EOF
fi
chown -R 1000:1000 "$rootfs/home/$admin_user"

printf '%s\n' "$lfs_hostname" >"$rootfs/etc/hostname"
cat >"$rootfs/etc/hosts" <<EOF
127.0.0.1 localhost
127.0.1.1 $lfs_hostname
::1 localhost ip6-localhost ip6-loopback
EOF
cat >"$rootfs/etc/fstab" <<'EOF'
/dev/vda1 / ext4 defaults 1 1
EOF
cat >"$rootfs/etc/os-release" <<'EOF'
NAME="XBee Linux From Scratch"
ID=xbee-lfs
VERSION="13.0"
VERSION_ID="13.0"
PRETTY_NAME="XBee Linux From Scratch 13.0"
EOF
cat >"$rootfs/etc/resolv.conf" <<'EOF'
nameserver 10.0.2.3
EOF
: >"$rootfs/etc/machine-id"

cat >"$rootfs/etc/locale.conf" <<'EOF'
LANG=en_US.UTF-8
EOF
cat >"$rootfs/etc/vconsole.conf" <<'EOF'
KEYMAP=us
EOF

cat >>"$rootfs/etc/ssh/sshd_config" <<EOF

PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
AllowUsers $admin_user
# The VirtualBox provider probes SSH once per second while the first-boot
# NoCloud service installs its key.  OpenSSH otherwise penalizes the source
# before provisioning has completed and keeps rejecting the provider probes.
PerSourcePenalties no
EOF
if [[ -n "$authorized_key" ]]; then
  printf '%s\n' "$authorized_key" \
    >"$rootfs/home/$admin_user/.ssh/authorized_keys"
else
  : >"$rootfs/home/$admin_user/.ssh/authorized_keys"
fi
chmod 0600 "$rootfs/home/$admin_user/.ssh/authorized_keys"
chown 1000:1000 "$rootfs/home/$admin_user/.ssh/authorized_keys"
printf '%s\n' "$admin_user ALL=(ALL) NOPASSWD: ALL" \
  >"$rootfs/etc/sudoers.d/$admin_user"
chmod 0440 "$rootfs/etc/sudoers.d/$admin_user"

install -m 0755 "$nocloud_agent" "$rootfs/usr/sbin/xbee-nocloud"
cat >"$rootfs/usr/lib/systemd/system/xbee-nocloud.service" <<EOF
[Unit]
Description=XBee minimal NoCloud first-boot provisioning
After=local-fs.target

[Service]
Type=oneshot
Environment=XBEE_NOCLOUD_USER=$admin_user
ExecStart=/usr/sbin/xbee-nocloud
StandardOutput=journal+console
StandardError=journal+console
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

cat >"$rootfs/usr/lib/systemd/system/dbus.service" <<'EOF'
[Unit]
Description=D-Bus System Message Bus
After=syslog.target

[Service]
Type=simple
RuntimeDirectory=dbus
RuntimeDirectoryMode=0755
ExecStart=/usr/bin/dbus-daemon --system --nofork --nopidfile --syslog-only
ExecReload=/usr/bin/dbus-send --print-reply --system --type=method_call --dest=org.freedesktop.DBus / org.freedesktop.DBus.ReloadConfig
OOMScoreAdjust=-900
EOF

ln -sfn /usr/lib/systemd/system/multi-user.target \
  "$rootfs/etc/systemd/system/default.target"
ln -sfn /usr/lib/systemd/system/sshd.service \
  "$rootfs/etc/systemd/system/multi-user.target.wants/sshd.service"
if [[ "$desktop_profile" == true ]]; then
  ln -sfn /usr/lib/systemd/system/NetworkManager.service \
    "$rootfs/etc/systemd/system/multi-user.target.wants/NetworkManager.service"
else
  ln -sfn /usr/lib/systemd/system/dhcpcd.service \
    "$rootfs/etc/systemd/system/multi-user.target.wants/dhcpcd.service"
fi
ln -sfn /usr/lib/systemd/system/dbus.service \
  "$rootfs/etc/systemd/system/multi-user.target.wants/dbus.service"
ln -sfn /usr/lib/systemd/system/xbee-nocloud.service \
  "$rootfs/etc/systemd/system/multi-user.target.wants/xbee-nocloud.service"

chroot "$rootfs" /usr/sbin/ldconfig
chroot "$rootfs" /usr/bin/ssh-keygen -A
chroot "$rootfs" /usr/sbin/sshd -t

configured_archive="$output_dir/package-rootfs.tar.zst"
metadata_file="$output_dir/package-system-metadata.yaml"
if [[ "$profile" != full ]]; then
  configured_archive="$output_dir/$profile-rootfs.tar.zst"
  metadata_file="$output_dir/$profile-system-metadata.yaml"
fi
tar --xattrs --acls --numeric-owner --zstd \
  -C "$rootfs" -cf "$configured_archive" .
(
  cd "$output_dir"
  sha256sum "$(basename "$configured_archive")" \
    >"$(basename "$configured_archive").sha256"
)

rootfs_mib=$(du -sm "$rootfs" | awk '{print $1}')
image_mib=$((rootfs_mib + extra_mib))
if ((image_mib < 4096)); then
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
    [[ "$number" =~ ^[0-9]+$ ]] || return 1
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
cp -a "$rootfs/." "$mount_dir/"

/usr/sbin/grub-install \
  --target=i386-pc \
  --boot-directory="$mount_dir/boot" \
  --modules="biosdisk part_msdos ext2 normal linux" \
  --recheck "$loop_device"
cat >"$mount_dir/boot/grub/grub.cfg" <<'EOF'
set default=0
set timeout=2

menuentry "XBee Linux From Scratch 13.0 (packages)" {
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

virtualbox_vmdk="$output_dir/$image_name-virtualbox.vmdk"
partition_loop_device=$(allocate_loop \
  --offset $((1024 * 1024)) \
  --sizelimit $(((image_mib - 1) * 1024 * 1024)))
mount "$partition_loop_device" "$mount_dir"
sed -i 's#root=/dev/vda1#root=/dev/sda1#' \
  "$mount_dir/boot/grub/grub.cfg"
grep -Fq 'root=/dev/sda1' "$mount_dir/boot/grub/grub.cfg"
sync
umount "$mount_dir"
losetup --detach "$partition_loop_device"
partition_loop_device=
qemu-img convert -f raw -O vmdk -o subformat=streamOptimized \
  "$raw_image" "$virtualbox_vmdk"
(
  cd "$output_dir"
  sha256sum "$(basename "$virtualbox_vmdk")" \
    >"$(basename "$virtualbox_vmdk").sha256"
)

cat >"$metadata_file" <<EOF
schema-version: 1
stage: package-system
profile: "$profile"
repository-version: "0.34.1"
package-count: $package_count
architecture: x86_64
kernel: "6.18.10"
init: systemd
hostname: "$lfs_hostname"
nocloud: xbee-nocloud
image:
  name: "$(basename "$qcow2")"
  format: qcow2
  firmware: bios
  partition-table: msdos
virtualbox:
  name: "$(basename "$virtualbox_vmdk")"
  format: vmdk
  root-device: /dev/sda1
rootfs: "$(basename "$configured_archive")"
EOF
