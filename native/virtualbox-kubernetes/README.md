# Kubernetes OS dans VirtualBox

Cet environnement démarre un nœud `kubernetes-os` avec 2 CPU et 4 Gio de
mémoire, puis vérifie le runtime CRI, kubelet, les modules réseau et le swap.

```bash
cd native/virtualbox-kubernetes
xbee validate
xbee pack
xbee up
xbee enter
```

Le test de démarrage complet est automatisé par `./smoke.sh`. Si KVM est
chargé, il faut d'abord arrêter les VM QEMU/KVM puis décharger temporairement
le module KVM, comme pour l'autre scénario VirtualBox du dépôt.

Initialisation d'un control plane de développement :

```bash
sudo kubeadm init --pod-network-cidr=<CIDR-DU-CNI>
```

L'image VMDK doit avoir été publiée avec la release indiquée dans le pack
`../kubernetes-os`. Pour un test avant publication, remplacer temporairement
la propriété `provider.virtualbox.disk` par l'URL du VMDK construit par
`package-kubernetes-system`.
