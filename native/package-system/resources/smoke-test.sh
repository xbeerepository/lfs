#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: smoke-test.sh IMAGE.qcow2 SSH_PRIVATE_KEY [bios|uefi]

Boot a package-system image, provision it through a NoCloud cidata seed, and
verify SSH, systemd, networking, the package database, critical package
payloads, HTTPS, sudo, rsync, kernel modules, and clean shutdown.

Environment:
  XBEELFS_ADMIN_USER    guest administrator (default: xbee)
  XBEELFS_HOSTNAME      expected guest hostname (default: xbee-lfs)
  XBEELFS_MEMORY_MIB    VM memory in MiB (default: 2048)
  XBEELFS_SSH_PORT      host SSH port (default: 2222)
  XBEELFS_TIMEOUT       boot timeout in seconds (default: 360)
  XBEELFS_KEEP_WORK     keep the temporary directory when set to true
EOF
}

if [[ $# -lt 2 || $# -gt 3 ]]; then
  usage
  exit 2
fi

image=$1
private_key=$2
firmware=${3:-bios}
admin_user=${XBEELFS_ADMIN_USER:-xbee}
expected_hostname=${XBEELFS_HOSTNAME:-xbee-lfs}
memory_mib=${XBEELFS_MEMORY_MIB:-2048}
ssh_port=${XBEELFS_SSH_PORT:-2222}
boot_timeout=${XBEELFS_TIMEOUT:-360}
keep_work=${XBEELFS_KEEP_WORK:-false}

[[ -f "$image" ]] || {
  echo "package-system image not found: $image" >&2
  exit 2
}
[[ -f "$private_key" ]] || {
  echo "SSH private key not found: $private_key" >&2
  exit 2
}
[[ "$firmware" == bios || "$firmware" == uefi ]] || {
  echo "firmware must be bios or uefi" >&2
  exit 2
}
[[ "$admin_user" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || {
  echo "invalid administrator name: $admin_user" >&2
  exit 2
}
[[ "$expected_hostname" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || {
  echo "invalid expected hostname: $expected_hostname" >&2
  exit 2
}
for value_name in memory_mib ssh_port boot_timeout; do
  value=${!value_name}
  [[ "$value" =~ ^[1-9][0-9]*$ ]] || {
    echo "$value_name must be a positive integer: $value" >&2
    exit 2
  }
done
for command_name in \
  qemu-img qemu-system-x86_64 realpath ssh ssh-keygen timeout xorriso; do
  command -v "$command_name" >/dev/null || {
    echo "required command not found: $command_name" >&2
    exit 1
  }
done
if timeout 1 bash -c "</dev/tcp/127.0.0.1/$ssh_port" 2>/dev/null; then
  echo "host TCP port is already in use: $ssh_port" >&2
  exit 1
fi

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/xbee-lfs-package-smoke.XXXXXX")
qemu_pid=
cleanup() {
  if [[ -n "$qemu_pid" ]] && kill -0 "$qemu_pid" 2>/dev/null; then
    kill "$qemu_pid" 2>/dev/null || true
    wait "$qemu_pid" 2>/dev/null || true
  fi
  if [[ "$keep_work" == true ]]; then
    echo "package smoke-test work directory: $work_dir"
  else
    case "$work_dir" in
      "${TMPDIR:-/tmp}"/xbee-lfs-package-smoke.*)
        find "$work_dir" -depth -delete
        ;;
      *)
        echo "refusing unexpected cleanup path: $work_dir" >&2
        ;;
    esac
  fi
}
trap cleanup EXIT INT TERM

overlay="$work_dir/package-system.qcow2"
serial_log="$work_dir/serial.log"
pid_file="$work_dir/qemu.pid"
seed_dir="$work_dir/seed"
mkdir "$seed_dir"
ssh-keygen -y -f "$private_key" >"$seed_dir/public-key"
cat >"$seed_dir/meta-data" <<EOF
instance-id: xbee-package-smoke-001
local-hostname: $expected_hostname
EOF
{
  printf '%s\n' '#cloud-config' 'ssh_authorized_keys:'
  printf '  - %s\n' "$(<"$seed_dir/public-key")"
} >"$seed_dir/user-data"
xorriso -as mkisofs -quiet \
  -volid cidata -joliet -rock \
  -output "$work_dir/seed.iso" \
  "$seed_dir/user-data" "$seed_dir/meta-data"

firmware_args=()
if [[ "$firmware" == uefi ]]; then
  ovmf_code=/usr/share/OVMF/OVMF_CODE_4M.fd
  ovmf_vars=/usr/share/OVMF/OVMF_VARS_4M.fd
  if [[ ! -f "$ovmf_code" || ! -f "$ovmf_vars" ]]; then
    echo "OVMF firmware not found under /usr/share/OVMF" >&2
    exit 1
  fi
  cp "$ovmf_vars" "$work_dir/OVMF_VARS_4M.fd"
  firmware_args=(
    -drive "if=pflash,format=raw,readonly=on,file=$ovmf_code"
    -drive "if=pflash,format=raw,file=$work_dir/OVMF_VARS_4M.fd"
  )
fi
qemu-img create -q -f qcow2 -F qcow2 -b "$(realpath "$image")" "$overlay"

qemu-system-x86_64 \
  -name "xbee-lfs-package-smoke-$firmware" \
  -machine q35,accel=kvm:tcg \
  -cpu max \
  -m "$memory_mib" \
  -display none \
  -serial "file:$serial_log" \
  -monitor none \
  -daemonize \
  -pidfile "$pid_file" \
  "${firmware_args[@]}" \
  -drive "file=$overlay,if=virtio,format=qcow2" \
  -drive "file=$work_dir/seed.iso,media=cdrom,readonly=on" \
  -nic "user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:$ssh_port-:22"
qemu_pid=$(cat "$pid_file")

ssh_options=(
  -i "$private_key"
  -o BatchMode=yes
  -o ConnectTimeout=2
  -o LogLevel=ERROR
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -p "$ssh_port"
)
deadline=$((SECONDS + boot_timeout))
ssh_ready=false
while ((SECONDS < deadline)); do
  if ! kill -0 "$qemu_pid" 2>/dev/null; then
    echo "QEMU stopped before SSH became ready" >&2
    tail -n 160 "$serial_log" >&2
    exit 1
  fi
  if ssh "${ssh_options[@]}" -q "$admin_user@127.0.0.1" true \
      2>/dev/null; then
    ssh_ready=true
    break
  fi
  sleep 2
done
if [[ "$ssh_ready" != true ]]; then
  echo "SSH did not become ready within ${boot_timeout}s" >&2
  tail -n 160 "$serial_log" >&2
  exit 1
fi

ssh "${ssh_options[@]}" "$admin_user@127.0.0.1" \
  "EXPECTED_HOSTNAME='$expected_hostname' bash -s" <<'EOF'
set -euo pipefail

test "$(hostname)" = "$EXPECTED_HOSTNAME"
test "$(uname -r)" = 6.18.10
test "$(sudo -n systemctl is-system-running)" = running
for service in sshd dhcpcd dbus systemd-logind xbee-nocloud; do
  test "$(sudo -n systemctl is-active "$service")" = active
done
test -f /var/lib/cloud/instance/boot-finished
test "$(< /var/lib/xbee-nocloud/instance-id)" = xbee-package-smoke-001
test "$(sudo -n systemctl --failed --no-legend | wc -l)" -eq 0
test "$(sudo -n id -u)" -eq 0
test "$(sudo -n xbpkg list | wc -l)" -eq 91
test "$(sudo -n xbpkg owner /usr/bin/curl)" = curl
for package in bash coreutils curl dhcpcd linux-kernel rsync; do
  sudo -n xbpkg verify "$package"
done
test "$(sudo -n find /var/lib/xbpkg/installed -mindepth 1 -maxdepth 1 \
  -type d | wc -l)" -eq 91
test "$(sudo -n find /var/lib/xbpkg/installed -mindepth 2 -maxdepth 2 \
  -name manifest.yaml -type f | wc -l)" -eq 91
test "$(sudo -n find /var/lib/xbpkg/installed -mindepth 2 -maxdepth 2 \
  -name files.sha256 -type f | wc -l)" -eq 91
sudo -n modinfo virtio_blk >/dev/null
sudo -n ip -4 -o address show scope global | grep -q ' inet '
curl --fail --silent --show-error --max-time 30 https://example.com/ >/dev/null
wget -q --timeout=30 -O /dev/null https://example.com/
source_file=$(mktemp)
target_file=$(mktemp)
printf '%s\n' xbee-package-smoke >"$source_file"
rsync -a "$source_file" "$target_file"
cmp "$source_file" "$target_file"
rm -f "$source_file" "$target_file"
EOF

echo "package-system boot, SSH, systemd, network, and 91 package checks passed"
ssh "${ssh_options[@]}" -q "$admin_user@127.0.0.1" \
  "sudo -n systemctl poweroff" 2>/dev/null || true
for _ in $(seq 1 30); do
  if ! kill -0 "$qemu_pid" 2>/dev/null; then
    qemu_pid=
    echo "package-system smoke test passed ($firmware)"
    exit 0
  fi
  sleep 1
done
echo "guest did not power off cleanly" >&2
exit 1
