#!/usr/bin/env bash
set -euo pipefail

env_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
xbee_bin=${XBEE_BIN:-xbee}
environment_touched=false

cleanup() {
  status=$?
  if "$environment_touched"; then
    (cd "$env_dir" && "$xbee_bin" delete --force) || true
  fi
  exit "$status"
}
trap cleanup EXIT INT TERM

cd "$env_dir"
"$xbee_bin" validate
"$xbee_bin" pack
environment_touched=true
"$xbee_bin" up

set +e
output=$(
  printf '%s\n' \
    'set -euo pipefail' \
    'sudo /usr/bin/systemctl is-enabled containerd.service' \
    'sudo /usr/bin/systemctl is-active containerd.service' \
    'sudo /usr/bin/systemctl is-enabled kubelet.service' \
    'test "$(/usr/sbin/sysctl -n net.ipv4.ip_forward)" = 1' \
    'grep -qw overlay /proc/modules' \
    'grep -qw br_netfilter /proc/modules' \
    'test "$(wc -l </proc/swaps)" = 1' \
    'sudo /usr/bin/crictl info >/dev/null' \
    '/usr/bin/kubeadm version -o short' \
    'echo XBEE_KUBERNETES_SMOKE_OK' \
    'exit' | "$xbee_bin" enter 2>&1
)
status=$?
set -e
printf '%s\n' "$output"
[[ $status -eq 0 ]]
grep -Fxq XBEE_KUBERNETES_SMOKE_OK <<<"$output"

"$xbee_bin" delete --force
environment_touched=false
echo "kubernetes-os VirtualBox smoke test passed"
