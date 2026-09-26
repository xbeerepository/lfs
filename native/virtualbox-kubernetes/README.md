# Kubernetes OS dans VirtualBox

Cet environnement démarre sept nœuds `kubernetes-os` sur le même réseau
VirtualBox : trois masters (`master1` à `master3`) et quatre workers
(`worker1` à `worker4`). Chaque machine dispose de 2 CPU et 4 Gio de mémoire.
Le pack vérifie le runtime CRI, kubelet, les modules réseau et le swap sur
chaque nœud.

```bash
cd native/virtualbox-kubernetes
xbee validate
xbee pack
xbee up
xbee enter master1
```

Pour tester une version locale du provider VirtualBox, construire le binaire
depuis le monorepo puis l'indiquer directement à XBee :

```bash
cd ~/xbee-projects/xbee-providers/providers/virtualbox
go build -trimpath -o ../../dist/xbee-virtualbox ./main

cd ~/xbee-projects/lfs/native/virtualbox-kubernetes
export XBEE_PROVIDER_BINARY=~/xbee-projects/xbee-providers/dist/xbee-virtualbox
xbee pack --non-interactive
xbee up
```

`xbee down` arrête les machines en conservant leurs disques.
`xbee delete --force` les supprime. Retirer `XBEE_PROVIDER_BINARY` avec `unset`
permet de revenir au provider publié.

Le test de démarrage complet est automatisé par `./smoke.sh`. Si KVM est
chargé, il faut d'abord arrêter les VM QEMU/KVM puis décharger temporairement
le module KVM, comme pour l'autre scénario VirtualBox du dépôt.

La création des machines ne forme pas automatiquement le cluster. Après leur
démarrage, initialiser le premier master, joindre les deux autres masters au
control plane, puis joindre les quatre workers avec les commandes produites par
`kubeadm` :

```bash
sudo kubeadm init --pod-network-cidr=<CIDR-DU-CNI>
```

L'image VMDK doit avoir été publiée avec la release indiquée dans le pack
`../kubernetes-os`. Pour un test avant publication, remplacer temporairement
la propriété `provider.virtualbox.disk` par l'URL du VMDK construit par
`package-kubernetes-system`.
