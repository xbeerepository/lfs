#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: smoke-test.sh RELEASE_ARCHIVE [bios|uefi|both]

Boot the release image(s), provision an ephemeral SSH key through NoCloud, and
verify the hostname, kernel, systemd, SSH, and passwordless sudo.

Environment:
  XBEELFS_MEMORY_MIB   VM memory in MiB (default: 2048)
  XBEELFS_SSH_PORT     first host SSH port (default: 2222)
  XBEELFS_TIMEOUT      boot timeout in seconds (default: 360)
  XBEELFS_KEEP_WORK    keep the temporary directory when set to true
EOF
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage
  exit 2
fi

archive=$1
firmware=${2:-both}
memory_mib=${XBEELFS_MEMORY_MIB:-2048}
ssh_port=${XBEELFS_SSH_PORT:-2222}
boot_timeout=${XBEELFS_TIMEOUT:-360}
keep_work=${XBEELFS_KEEP_WORK:-false}

if [[ ! -f "$archive" ]]; then
  echo "release archive not found: $archive" >&2
  exit 2
fi
if [[ "$firmware" != bios && "$firmware" != uefi && "$firmware" != both ]]; then
  echo "firmware must be bios, uefi, or both" >&2
  exit 2
fi
for value_name in memory_mib ssh_port boot_timeout; do
  value=${!value_name}
  if [[ ! "$value" =~ ^[1-9][0-9]*$ ]]; then
    echo "$value_name must be a positive integer: $value" >&2
    exit 2
  fi
done

required_commands=(
  base64 qemu-img qemu-system-x86_64 ssh ssh-keygen sha256sum tar timeout xorriso
)
for command_name in "${required_commands[@]}"; do
  if ! command -v "$command_name" >/dev/null; then
    echo "required command not found: $command_name" >&2
    exit 1
  fi
done

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/xbee-lfs-smoke.XXXXXX")
qemu_pid=
cleanup() {
  if [[ -n "$qemu_pid" ]] && kill -0 "$qemu_pid" 2>/dev/null; then
    kill "$qemu_pid" 2>/dev/null || true
    wait "$qemu_pid" 2>/dev/null || true
  fi
  if [[ "$keep_work" == true ]]; then
    echo "smoke-test work directory: $work_dir"
  else
    rm -rf "$work_dir"
  fi
}
trap cleanup EXIT INT TERM

tar --zstd -xf "$archive" -C "$work_dir"
release_dir=$(find "$work_dir" -mindepth 1 -maxdepth 1 -type d -print -quit)
if [[ -z "$release_dir" || ! -f "$release_dir/SHA256SUMS" ]]; then
  echo "invalid release archive: release directory or SHA256SUMS not found" >&2
  exit 1
fi
(
  cd "$release_dir"
  sha256sum -c SHA256SUMS
)

ssh-keygen -q -t ed25519 -N "" -f "$work_dir/id_ed25519"
mkdir -p "$work_dir/seed"
cat >"$work_dir/seed/meta-data" <<'EOF'
instance-id: xbee-smoke-001
local-hostname: xbee-smoke
EOF
authorized_script=$(printf '%s\n' \
  '#!/bin/bash' \
  'set -eu' \
  'install -d -m 0700 -o xbee -g xbee /home/xbee/.ssh' \
  "printf '%s\\n' '$(cat "$work_dir/id_ed25519.pub")' > /home/xbee/.ssh/authorized_keys" \
  'chown xbee:xbee /home/xbee/.ssh/authorized_keys' \
  'chmod 0600 /home/xbee/.ssh/authorized_keys' \
  'systemctl restart sshd' |
  base64 -w0)
{
  printf '%s\n' \
    "#cloud-config" \
    "write_files:" \
    "  - encoding: b64" \
    "    content: $authorized_script" \
    "    owner: root:root" \
    "    path: /run/authorized-data.sh" \
    "runcmd:" \
    "  - bash /run/authorized-data.sh"
} >"$work_dir/seed/user-data"
xorriso -as mkisofs -quiet \
  -volid cidata -joliet -rock \
  -output "$work_dir/seed.iso" \
  "$work_dir/seed/user-data" "$work_dir/seed/meta-data"

ssh_options=(
  -i "$work_dir/id_ed25519"
  -o BatchMode=yes
  -o ConnectTimeout=2
  -o LogLevel=ERROR
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
)

wait_for_ssh() {
  local port=$1
  local deadline=$((SECONDS + boot_timeout))

  while ((SECONDS < deadline)); do
    if ! kill -0 "$qemu_pid" 2>/dev/null; then
      echo "QEMU stopped before SSH became ready" >&2
      return 1
    fi
    if ssh "${ssh_options[@]}" -q -p "$port" xbee@127.0.0.1 true \
        2>/dev/null; then
      return 0
    fi
    sleep 2
  done
  echo "SSH did not become ready within ${boot_timeout}s" >&2
  return 1
}

boot_and_check() {
  local mode=$1
  local port=$2
  local image serial_log disk pid_file
  local -a firmware_args=()

  if timeout 1 bash -c "</dev/tcp/127.0.0.1/$port" 2>/dev/null; then
    echo "host TCP port is already in use: $port" >&2
    return 1
  fi

  if [[ "$mode" == bios ]]; then
    image=$(find "$release_dir/images" -maxdepth 1 -type f \
      -name '*-cloud.qcow2' -print -quit)
  else
    image=$(find "$release_dir/images" -maxdepth 1 -type f \
      -name '*-uefi.qcow2' -print -quit)
    local ovmf_code=/usr/share/OVMF/OVMF_CODE_4M.fd
    local ovmf_vars=/usr/share/OVMF/OVMF_VARS_4M.fd
    if [[ ! -f "$ovmf_code" || ! -f "$ovmf_vars" ]]; then
      echo "OVMF firmware not found under /usr/share/OVMF" >&2
      return 1
    fi
    cp "$ovmf_vars" "$work_dir/OVMF_VARS_4M.fd"
    firmware_args=(
      -drive "if=pflash,format=raw,readonly=on,file=$ovmf_code"
      -drive "if=pflash,format=raw,file=$work_dir/OVMF_VARS_4M.fd"
    )
  fi
  if [[ -z "$image" ]]; then
    echo "$mode image not found in release archive" >&2
    return 1
  fi

  disk="$work_dir/$mode.qcow2"
  serial_log="$work_dir/$mode-serial.log"
  pid_file="$work_dir/$mode.pid"
  qemu-img create -q -f qcow2 -F qcow2 -b "$image" "$disk"

  echo "[$mode] booting $(basename "$image") on SSH port $port"
  qemu-system-x86_64 \
    -name "xbee-lfs-smoke-$mode" \
    -machine q35,accel=kvm:tcg \
    -m "$memory_mib" \
    -display none \
    -serial "file:$serial_log" \
    -monitor none \
    -daemonize \
    -pidfile "$pid_file" \
    "${firmware_args[@]}" \
    -drive "file=$disk,if=virtio,format=qcow2" \
    -drive "file=$work_dir/seed.iso,media=cdrom,readonly=on" \
    -nic "user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:$port-:22"
  qemu_pid=$(cat "$pid_file")

  if ! wait_for_ssh "$port"; then
    tail -n 160 "$serial_log" >&2
    return 1
  fi

  ssh "${ssh_options[@]}" -p "$port" xbee@127.0.0.1 '
    set -eu
    test "$(hostname)" = xbee-smoke
    test "$(uname -r)" = 6.18.10
    test "$(systemctl is-system-running)" = running
    test "$(systemctl is-active sshd)" = active
    test -f /var/lib/cloud/instance/boot-finished
    test -s "$HOME/.ssh/authorized_keys"
    sudo -n test "$(id -u)" = 1000
    test "$(sudo -n id -u)" = 0
  '
  echo "[$mode] boot, NoCloud, SSH, systemd, and sudo checks passed"

  ssh "${ssh_options[@]}" -q -p "$port" xbee@127.0.0.1 \
    "sudo -n poweroff" 2>/dev/null || true
  for _ in $(seq 1 30); do
    if ! kill -0 "$qemu_pid" 2>/dev/null; then
      qemu_pid=
      return 0
    fi
    sleep 1
  done
  echo "[$mode] guest did not power off cleanly" >&2
  return 1
}

case "$firmware" in
  bios)
    boot_and_check bios "$ssh_port"
    ;;
  uefi)
    boot_and_check uefi "$ssh_port"
    ;;
  both)
    boot_and_check bios "$ssh_port"
    boot_and_check uefi "$((ssh_port + 1))"
    ;;
esac

echo "LFS release smoke test passed ($firmware)"
