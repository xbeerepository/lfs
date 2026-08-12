#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
env_file="$repo_root/native/virtualbox-kubernetes/xbee-env.yaml"
pack_file="$repo_root/native/virtualbox-kubernetes/pack/xbee-pack.yaml"
system_file="$repo_root/native/kubernetes-os/xbee-pack-system.yaml"

grep -Fq 'name: virtualbox' "$env_file"
grep -Fq 'cpus: 2' "$env_file"
grep -Fq 'memory: 4096' "$env_file"
grep -Fq 'system: ../kubernetes-os' "$env_file"
grep -Fq 'systemctl is-active containerd.service' "$pack_file"
grep -Fq 'kubernetes-os-13.0-x86_64-virtualbox.vmdk' "$system_file"

echo "kubernetes-os VirtualBox environment is coherent"
