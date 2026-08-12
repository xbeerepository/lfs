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
    'test "$(. /etc/os-release; printf %s "$ID")" = xbee-lfs' \
    'sudo /usr/bin/systemctl is-active sshd.service' \
    'sudo /usr/bin/systemctl is-active dhcpcd.service' \
    '/usr/bin/xbpkg list > /tmp/xbee-os-packages' \
    'grep -q "^linux-kernel " /tmp/xbee-os-packages' \
    'grep -q "^openssh " /tmp/xbee-os-packages' \
    'echo XBEE_OS_VIRTUALBOX_SMOKE_OK' \
    'exit' | "$xbee_bin" enter 2>&1
)
status=$?
set -e
printf '%s\n' "$output"
[[ $status -eq 0 ]]
grep -Fxq XBEE_OS_VIRTUALBOX_SMOKE_OK <<<"$output"

"$xbee_bin" delete --force
environment_touched=false
echo "XBee OS VirtualBox smoke test passed"
