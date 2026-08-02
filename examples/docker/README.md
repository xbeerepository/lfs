# LFS avec Docker

Cet environnement exécute le système XBee LFS dans le provider Docker interne
de XBee. Contrairement à l'exemple VirtualBox, il utilise le root filesystem
produit par `native/system-rootfs` et ne démarre ni noyau LFS ni machine
virtuelle.

## Prérequis

- XBee installé ;
- Docker démarré ;
- les prérequis de construction LFS décrits à la racine du dépôt.

Le premier `xbee pack` construit la chaîne LFS native locale. Cette opération
compile le système complet et peut durer plusieurs heures.

## Lancer l'environnement

Depuis ce répertoire :

```bash
xbee validate
xbee pack
xbee up
```

Entrer dans le conteneur :

```bash
xbee enter
```

Arrêter l'environnement :

```bash
xbee down
```

Le supprimer avec ses ressources :

```bash
xbee delete
```

Le provider Docker étant interne à XBee, `xbee-env.yaml` ne contient
volontairement aucun bloc `provider`.
