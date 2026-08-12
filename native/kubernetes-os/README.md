# Kubernetes OS

`kubernetes-os` est un système XBee fondé sur XBee OS 13.0 et préparé pour
servir de nœud Kubernetes 1.36.2 avec `kubeadm`.

Il contient containerd 2.3.1, runc 1.5.1, les plugins CNI 1.9.1,
cri-tools 1.36.0, kubelet, kubeadm et kubectl. Containerd et kubelet utilisent
le pilote cgroup systemd. Le forwarding IPv4, `overlay` et `br_netfilter` sont
configurés ; le swap est désactivé.

```bash
cd native/kubernetes-os
xbee validate
xbee pack
```

L'image disque amorçable est produite séparément :

```bash
xbee builder build ../package-kubernetes-system
```

Après démarrage, initialiser le premier control plane puis installer le CNI de
votre choix :

```bash
kubeadm init --pod-network-cidr=<CIDR-DU-CNI>
```

Le pack ne choisit volontairement aucun CNI de cluster. Les binaires CNI de
base sont installés sous `/usr/lib/cni`.
