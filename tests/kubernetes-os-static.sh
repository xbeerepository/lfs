#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
profile="$repo_root/native/package-system-tools/resources/profiles/kubernetes.txt"
config="$repo_root/native/package-kubernetes-components/resources/build.sh"
manifest="$repo_root/native/kubernetes-sources/resources/sources.tsv"

for package in containerd runc cni-plugins cri-tools kubeadm kubelet kubectl; do
  grep -Fxq "$package" "$profile"
done
[[ $(grep -vc '^#\|^[[:space:]]*$' "$manifest") -eq 7 ]]
grep -Fq 'SystemdCgroup = true' "$config"
grep -Fq 'net.ipv4.ip_forward = 1' "$config"
grep -Fq 'overlay br_netfilter' "$config"
grep -Fq 'containerd.service' "$config"
grep -Fq 'kubelet.service' "$config"

echo "kubernetes-os package profile and node configuration are coherent"
