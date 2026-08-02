#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: smoke-test.sh IMAGE.qcow2 REPOSITORY.tar SSH_PRIVATE_KEY" >&2
  exit 2
fi

image=$1
repository_archive=$2
private_key=$3
ssh_port=${XBEELFS_SSH_PORT:-2222}
http_port=${XBEELFS_HTTP_PORT:-18080}
boot_timeout=${XBEELFS_TIMEOUT:-360}
keep_work=${XBEELFS_KEEP_WORK:-false}

for file in "$image" "$repository_archive" "$private_key"; do
  [[ -f "$file" ]] || { echo "file not found: $file" >&2; exit 2; }
done
for command_name in python3 qemu-img qemu-system-x86_64 realpath ssh \
  ssh-keygen timeout xorriso; do
  command -v "$command_name" >/dev/null ||
    { echo "required command not found: $command_name" >&2; exit 1; }
done
for port in "$ssh_port" "$http_port"; do
  if timeout 1 bash -c "</dev/tcp/127.0.0.1/$port" 2>/dev/null; then
    echo "host TCP port is already in use: $port" >&2
    exit 1
  fi
done

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/xbee-lfs-minimal-smoke.XXXXXX")
qemu_pid=
http_pid=
cleanup() {
  for pid in "$qemu_pid" "$http_pid"; do
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
    fi
  done
  if [[ "$keep_work" == true ]]; then
    echo "minimal smoke-test work directory: $work_dir"
  else
    case "$work_dir" in
      "${TMPDIR:-/tmp}"/xbee-lfs-minimal-smoke.*)
        [[ ! -d "$work_dir" ]] || find "$work_dir" -depth -delete
        ;;
      *) echo "refusing unexpected cleanup path: $work_dir" >&2 ;;
    esac
  fi
}
trap cleanup EXIT INT TERM

tar -xf "$repository_archive" -C "$work_dir"
repository="$work_dir/opt/xbee-lfs-repository"
for file in index.yaml RELEASE SHA256SUMS SHA256SUMS.sig \
  SHA256SUMS.keyid repository-ed25519-public.pem; do
  [[ -f "$repository/$file" ]] ||
    { echo "repository file not found: $file" >&2; exit 1; }
done
python3 -m http.server "$http_port" --bind 0.0.0.0 \
  --directory "$repository" >"$work_dir/http.log" 2>&1 &
http_pid=$!

seed_dir="$work_dir/seed"
mkdir "$seed_dir"
ssh-keygen -y -f "$private_key" >"$seed_dir/public-key"
cat >"$seed_dir/meta-data" <<'EOF'
instance-id: xbee-minimal-smoke-001
local-hostname: xbee-lfs-minimal
EOF
{
  printf '%s\n' '#cloud-config' 'ssh_authorized_keys:'
  printf '  - %s\n' "$(<"$seed_dir/public-key")"
} >"$seed_dir/user-data"
xorriso -as mkisofs -quiet -volid cidata -joliet -rock \
  -output "$work_dir/seed.iso" \
  "$seed_dir/user-data" "$seed_dir/meta-data"

overlay="$work_dir/minimal.qcow2"
serial_log="$work_dir/serial.log"
pid_file="$work_dir/qemu.pid"
qemu-img create -q -f qcow2 -F qcow2 -b "$(realpath "$image")" "$overlay"
qemu-system-x86_64 \
  -name xbee-lfs-minimal-smoke \
  -machine q35,accel=kvm:tcg -cpu max -m 2048 \
  -display none -serial "file:$serial_log" -monitor none \
  -daemonize -pidfile "$pid_file" \
  -drive "file=$overlay,if=virtio,format=qcow2" \
  -drive "file=$work_dir/seed.iso,media=cdrom,readonly=on" \
  -nic "user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:$ssh_port-:22"
qemu_pid=$(<"$pid_file")

ssh_options=(
  -i "$private_key" -o BatchMode=yes -o ConnectTimeout=2
  -o LogLevel=ERROR -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null -p "$ssh_port"
)
wait_for_ssh() {
  local deadline=$((SECONDS + boot_timeout))
  while ((SECONDS < deadline)); do
    if ! kill -0 "$qemu_pid" 2>/dev/null; then
      echo "QEMU stopped before SSH became ready" >&2
      tail -n 160 "$serial_log" >&2
      return 1
    fi
    if ssh "${ssh_options[@]}" -q xbee@127.0.0.1 true 2>/dev/null; then
      return 0
    fi
    sleep 2
  done
  echo "SSH did not become ready within ${boot_timeout}s" >&2
  tail -n 160 "$serial_log" >&2
  return 1
}
wait_for_ssh

ssh "${ssh_options[@]}" xbee@127.0.0.1 \
  "REPOSITORY_URL='http://10.0.2.2:$http_port' bash -s" <<'EOF'
set -euo pipefail
test "$(hostname)" = xbee-lfs-minimal
test "$(sudo -n systemctl is-system-running)" = running
test "$(sudo -n xbpkg list | wc -l)" -eq 44
test ! -e /usr/bin/curl
test -x /usr/bin/wget
sudo -n install -d /etc/xbpkg/repositories.d /etc/xbpkg/trusted-keys
sudo -n wget -q -O /etc/xbpkg/trusted-keys/xbee-lfs.pem \
  "$REPOSITORY_URL/repository-ed25519-public.pem"
sudo -n tee /etc/xbpkg/repositories.d/xbee-lfs.conf >/dev/null <<CONF
name: "xbee-lfs"
location: "$REPOSITORY_URL"
key: "/etc/xbpkg/trusted-keys/xbee-lfs.pem"
CONF
sudo -n xbpkg refresh
sudo -n xbpkg install curl
test -x /usr/bin/curl
sudo -n xbpkg verify curl
curl --fail --silent --show-error --max-time 30 "$REPOSITORY_URL/RELEASE" \
  >/dev/null
test "$(sudo -n xbpkg list | wc -l)" -eq 45
sudo -n systemctl reboot
EOF

sleep 3
wait_for_ssh
ssh "${ssh_options[@]}" xbee@127.0.0.1 <<'EOF'
set -euo pipefail
test -x /usr/bin/curl
sudo -n xbpkg verify curl
test "$(sudo -n xbpkg owner /usr/bin/curl)" = curl
test "$(sudo -n xbpkg list | wc -l)" -eq 45
test "$(sudo -n systemctl is-system-running)" = running
sudo -n systemctl poweroff
EOF

for _ in $(seq 1 30); do
  if ! kill -0 "$qemu_pid" 2>/dev/null; then
    qemu_pid=
    echo "minimal image HTTP repository install and reboot test passed"
    exit 0
  fi
  sleep 1
done
echo "guest did not power off cleanly" >&2
exit 1
