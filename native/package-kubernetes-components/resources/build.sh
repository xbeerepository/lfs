#!/usr/bin/env bash
set -euo pipefail

sources=$1
source_root=$2
output_root=$3
work="$source_root/kubernetes-packages"
packages="$output_root/opt/xbee-lfs-packages"
rm -rf "$work"
mkdir -p "$work" "$packages"

make_package() {
  local name=$1 version=$2 dependencies=$3 stage=$4
  local metadata="$work/metadata-$name"
  mkdir -p "$metadata/.XBPKG" "$metadata/rootfs"
  cp -a "$stage/." "$metadata/rootfs/"
  (cd "$metadata/rootfs" &&
    find . \( -type f -o -type l \) -printf '/%P\n' | LC_ALL=C sort >../.XBPKG/files &&
    find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum >../.XBPKG/files.sha256 &&
    if [[ -d etc ]]; then find etc -type f -printf '/%p\n' | LC_ALL=C sort >../.XBPKG/conffiles; else : >../.XBPKG/conffiles; fi)
  cat >"$metadata/.XBPKG/manifest.yaml" <<EOF
schema-version: 1
name: "$name"
version: "$version"
architecture: x86_64
dependencies: "$dependencies"
payload: rootfs
files: .XBPKG/files
checksums: .XBPKG/files.sha256
conffiles: .XBPKG/conffiles
EOF
  local archive="$packages/$name-$version-x86_64.xbpkg.tar.zst"
  tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner --zstd \
    -C "$metadata" -cf "$archive" .XBPKG rootfs
  (cd "$packages" && sha256sum "$(basename "$archive")" >"$(basename "$archive").sha256")
}

stage="$work/stage-containerd"
mkdir -p "$stage/usr/bin" "$stage/usr/lib/systemd/system" \
  "$stage/etc/containerd" "$stage/etc/cni/net.d" \
  "$stage/etc/modules-load.d" "$stage/etc/sysctl.d" \
  "$stage/etc/systemd/system/kubelet.service.d" \
  "$stage/etc/systemd/system/multi-user.target.wants"
tar -xf "$sources/containerd-static-2.3.1-linux-amd64.tar.gz" -C "$stage/usr"
cat >"$stage/usr/lib/systemd/system/containerd.service" <<'EOF'
[Unit]
Description=containerd container runtime
After=network.target local-fs.target
[Service]
ExecStart=/usr/bin/containerd
Restart=always
Delegate=yes
KillMode=process
[Install]
WantedBy=multi-user.target
EOF
cat >"$stage/etc/containerd/config.toml" <<'EOF'
version = 3
[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc]
  runtime_type = 'io.containerd.runc.v2'
  [plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc.options]
    SystemdCgroup = true
EOF
printf '%s\n' overlay br_netfilter >"$stage/etc/modules-load.d/kubernetes.conf"
cat >"$stage/etc/sysctl.d/99-kubernetes.conf" <<'EOF'
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
cat >"$stage/usr/lib/systemd/system/kubelet.service" <<'EOF'
[Unit]
Description=Kubernetes Kubelet
After=containerd.service network-online.target
Wants=network-online.target
[Service]
ExecStart=/usr/bin/kubelet
Restart=always
StartLimitInterval=0
[Install]
WantedBy=multi-user.target
EOF
cat >"$stage/etc/systemd/system/kubelet.service.d/10-kubeadm.conf" <<'EOF'
[Service]
Environment="KUBELET_KUBECONFIG_ARGS=--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf"
Environment="KUBELET_CONFIG_ARGS=--config=/var/lib/kubelet/config.yaml"
EnvironmentFile=-/var/lib/kubelet/kubeadm-flags.env
EnvironmentFile=-/etc/default/kubelet
ExecStart=
ExecStart=/usr/bin/kubelet $KUBELET_KUBECONFIG_ARGS $KUBELET_CONFIG_ARGS $KUBELET_KUBEADM_ARGS $KUBELET_EXTRA_ARGS
EOF
cat >"$stage/etc/crictl.yaml" <<'EOF'
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
EOF
ln -s /usr/lib/systemd/system/containerd.service "$stage/etc/systemd/system/multi-user.target.wants/containerd.service"
ln -s /usr/lib/systemd/system/kubelet.service "$stage/etc/systemd/system/multi-user.target.wants/kubelet.service"
ln -s /dev/null "$stage/etc/systemd/system/swap.target"
make_package containerd 2.3.1 "runc,cni-plugins,systemd" "$stage"

stage="$work/stage-runc"; mkdir -p "$stage/usr/bin"; install -m 0755 "$sources/runc.amd64" "$stage/usr/bin/runc"
make_package runc 1.5.1 "glibc" "$stage"

stage="$work/stage-cni"; mkdir -p "$stage/usr/lib/cni"; tar -xf "$sources/cni-plugins-linux-amd64-v1.9.1.tgz" -C "$stage/usr/lib/cni"
make_package cni-plugins 1.9.1 "glibc" "$stage"

stage="$work/stage-cri"; mkdir -p "$stage/usr/bin"; tar -xf "$sources/crictl-v1.36.0-linux-amd64.tar.gz" -C "$stage/usr/bin"; make_package cri-tools 1.36.0 "glibc" "$stage"

for binary in kubeadm kubelet kubectl; do
  stage="$work/stage-$binary"; mkdir -p "$stage/usr/bin"; install -m 0755 "$sources/$binary" "$stage/usr/bin/$binary"
  dependencies=glibc
  [[ "$binary" != kubelet ]] || dependencies="glibc,containerd"
  make_package "$binary" 1.36.2 "$dependencies" "$stage"
done
