# Kubernetes OS dans VirtualBox

Cet environnement démarre sept nœuds Kubernetes basés sur Ubuntu 26.04 sur le même réseau
VirtualBox : trois masters (`master1` à `master3`) et quatre workers
(`worker1` à `worker4`). Chaque machine dispose de 2 CPU et 4 Gio de mémoire.
Le pack système local `./system` installe Kubernetes 1.37 depuis le dépôt
officiel, configure containerd avec le pilote cgroup systemd, charge les
modules réseau et désactive le swap. Le pack hôte vérifie ces prérequis sur
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

Le système étend `ubuntu:26.04` et utilise donc directement l'image VirtualBox
définie par le pack système Ubuntu ; aucune image Kubernetes spécifique ne doit
être reconstruite ou publiée.
