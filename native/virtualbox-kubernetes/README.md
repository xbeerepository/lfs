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

Le script `environment.sh` permet ensuite de gérer l'ensemble des machines :

```bash
./environment.sh start
./environment.sh stop
./environment.sh restart
```

Ces opérations correspondent respectivement à `xbee up`, `xbee down`, puis
`xbee down` suivi de `xbee up`. Au démarrage, le script construit si nécessaire
le provider depuis le dépôt frère `virtualbox-provider`, raccorde le VMDK local
`dist/kubernetes-os-v1.37.0` au cache XBee, puis exécute `xbee pack`. Les chemins
peuvent être remplacés avec `XBEE_VIRTUALBOX_SOURCE`,
`XBEE_PROVIDER_BINARY`, `XBEE_GUEST_BINARY` et `XBEE_KUBERNETES_VMDK`.
L'arrêt conserve les machines et leurs disques.
`xbee delete --force` reste la commande à utiliser pour les supprimer.

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
