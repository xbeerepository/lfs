#!/usr/bin/env bash
set -euo pipefail

env_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
xbee_bin=${XBEE_BIN:-xbee}
vip=${KUBERNETES_VIP:-192.168.107.50}
interface=${KUBERNETES_INTERFACE:-enp0s8}
pod_cidr=${KUBERNETES_POD_CIDR:-10.244.0.0/16}
kube_vip_version=${KUBE_VIP_VERSION:-v1.2.3}
flannel_manifest=${FLANNEL_MANIFEST:-https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml}
masters=(master1 master2 master3)
workers=(worker1 worker2 worker3 worker4)
nodes=("${masters[@]}" "${workers[@]}")

cd "$env_dir"

run_node() {
  local node=$1
  local script=$2
  printf '%s\n' 'set -euo pipefail' "$script" | "$xbee_bin" enter "$node"
}

capture_node() {
  local node=$1
  local script=$2
  run_node "$node" "$script" 2>&1 | sed -n 's/^XBEE_VALUE=//p' | tail -n 1 | tr -d '\r'
}

node_ip() {
  capture_node "$1" "ip_value=\$(ip -4 -o address show dev '$interface' | awk '\$4 !~ /\\/32$/ {print \$4; exit}' | cut -d/ -f1); echo XBEE_VALUE=\$ip_value"
}

install_kube_vip_manifest() {
  local node=$1
  local kubeconfig_path=$2
  run_node "$node" "
sudo install -d -m 0755 /etc/kubernetes/manifests
sudo ctr images pull --platform linux/amd64 'ghcr.io/kube-vip/kube-vip:$kube_vip_version'
sudo ctr run --rm --net-host 'ghcr.io/kube-vip/kube-vip:$kube_vip_version' kube-vip-manifest /kube-vip \\
  manifest pod --interface '$interface' --address '$vip' --controlplane --arp --leaderElection \\
  | sed 's#/etc/kubernetes/admin.conf#$kubeconfig_path#g' \\
  | sudo tee /etc/kubernetes/manifests/kube-vip.yaml >/dev/null
"
}

echo "Discovering node addresses on $interface"
declare -A addresses
for node in "${nodes[@]}"; do
  addresses[$node]=$(node_ip "$node")
  if [[ ! ${addresses[$node]} =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Unable to discover the $interface IPv4 address for $node" >&2
    exit 1
  fi
  printf '  %-8s %s\n' "$node" "${addresses[$node]}"
done

if printf '%s\n' "${addresses[@]}" | grep -Fxq "$vip"; then
  echo "The VIP $vip is already assigned to a node" >&2
  exit 1
fi

echo "Resetting any existing Kubernetes state"
for node in "${nodes[@]}"; do
  run_node "$node" "
sudo kubeadm reset --force || true
sudo rm -f /etc/kubernetes/manifests/kube-vip.yaml
sudo rm -rf /etc/cni/net.d/* /home/ubuntu/.kube
sudo ip link delete cni0 2>/dev/null || true
sudo ip link delete flannel.1 2>/dev/null || true
echo 'KUBELET_EXTRA_ARGS=--node-ip=${addresses[$node]}' | sudo tee /etc/default/kubelet >/dev/null
sudo systemctl restart containerd kubelet
"
done

echo "Bootstrapping master1 with control-plane endpoint $vip:6443"
install_kube_vip_manifest master1 /etc/kubernetes/super-admin.conf
run_node master1 "
sudo kubeadm init \\
  --apiserver-advertise-address='${addresses[master1]}' \\
  --control-plane-endpoint='$vip:6443' \\
  --apiserver-cert-extra-sans='$vip' \\
  --pod-network-cidr='$pod_cidr' \\
  --upload-certs
sudo sed -i 's#/etc/kubernetes/super-admin.conf#/etc/kubernetes/admin.conf#g' /etc/kubernetes/manifests/kube-vip.yaml
sudo install -d -o ubuntu -g ubuntu -m 0700 /home/ubuntu/.kube
sudo install -o ubuntu -g ubuntu -m 0600 /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
"

join_command=$(capture_node master1 "join_value=\$(sudo kubeadm token create --ttl 2h --print-join-command); echo XBEE_VALUE=\$join_value")
certificate_key=$(capture_node master1 "sudo kubeadm init phase upload-certs --upload-certs --kubeconfig=/etc/kubernetes/super-admin.conf | tail -n 1 | sed 's/^/XBEE_VALUE=/'")
if [[ -z $join_command || -z $certificate_key ]]; then
  echo "Unable to obtain kubeadm join credentials" >&2
  exit 1
fi

for node in master2 master3; do
  echo "Joining $node to the control plane"
  run_node "$node" "sudo $join_command --control-plane --certificate-key '$certificate_key' --apiserver-advertise-address='${addresses[$node]}'"
  install_kube_vip_manifest "$node" /etc/kubernetes/admin.conf
done

for node in "${workers[@]}"; do
  echo "Joining $node as a worker"
  run_node "$node" "sudo $join_command"
done

echo "Installing Flannel on $interface"
run_node master1 "curl -fsSL '$flannel_manifest' \\
  | sed '/^[[:space:]]*- --ip-masq[[:space:]]*\$/a\\        - --iface=$interface' \\
  | sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f -"

echo "Waiting for all nodes and system pods"
run_node master1 "
kubectl wait --for=condition=Ready nodes --all --timeout=5m
kubectl -n kube-system wait --for=condition=Ready pod -l k8s-app=kube-dns --timeout=5m
kubectl -n kube-flannel wait --for=condition=Ready pod -l app=flannel --timeout=5m
kubectl get nodes -o wide
"

echo "Running a Service and DNS smoke test"
run_node master1 "
kubectl create namespace smoke-test 2>/dev/null || true
kubectl -n smoke-test create deployment web --image=nginx:1.28-alpine --replicas=4 2>/dev/null || true
kubectl -n smoke-test expose deployment web --port=80 2>/dev/null || true
kubectl -n smoke-test rollout status deployment/web --timeout=5m
kubectl -n smoke-test delete pod dns-client --ignore-not-found
kubectl -n smoke-test run dns-client --image=busybox:1.37 --restart=Never --command -- \\
  sh -c 'until wget -qO- http://web >/tmp/result; do sleep 2; done; grep -q Welcome /tmp/result'
kubectl -n smoke-test wait --for=jsonpath='{.status.phase}'=Succeeded pod/dns-client --timeout=3m
"

echo "Cluster ready: https://$vip:6443"
