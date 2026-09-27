#!/usr/bin/env bash
set -euo pipefail

env_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
xbee_bin=${XBEE_BIN:-xbee}
vip=${KUBERNETES_VIP:-192.168.107.50}
interface=${KUBERNETES_INTERFACE:-enp0s8}
masters=(master1 master2 master3)

cd "$env_dir"

run_node() {
  local node=$1
  local script=$2
  printf '%s\n' 'set -euo pipefail' "$script" | "$xbee_bin" enter "$node"
}

leader=
for node in "${masters[@]}"; do
  if run_node "$node" "ip -4 -o address show dev '$interface' | grep -Fq ' $vip/32 '" >/dev/null 2>&1; then
    leader=$node
    break
  fi
done

if [[ -z $leader ]]; then
  echo "No control-plane node currently owns VIP $vip" >&2
  exit 1
fi

restore_manifest() {
  run_node "$leader" "sudo mv /etc/kubernetes/manifests/kube-vip.yaml.ha-test /etc/kubernetes/manifests/kube-vip.yaml 2>/dev/null || true" >/dev/null || true
}
trap restore_manifest EXIT INT TERM

echo "Current VIP leader: $leader"
run_node "$leader" "sudo mv /etc/kubernetes/manifests/kube-vip.yaml /etc/kubernetes/manifests/kube-vip.yaml.ha-test"

echo "Waiting for the VIP to move away from $leader"
for _ in $(seq 1 30); do
  for node in "${masters[@]}"; do
    if [[ $node != "$leader" ]] && run_node "$node" "ip -4 -o address show dev '$interface' | grep -Fq ' $vip/32 '" >/dev/null 2>&1; then
      new_leader=$node
      break 2
    fi
  done
  sleep 1
done

if [[ -z ${new_leader:-} ]]; then
  echo "The VIP did not fail over within 30 seconds" >&2
  exit 1
fi

run_node worker1 "curl --fail --insecure --silent --max-time 5 'https://$vip:6443/livez' | grep -Fxq ok"
echo "VIP failover succeeded: $leader -> $new_leader"

restore_manifest
trap - EXIT INT TERM
