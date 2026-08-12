# XBee OS

`xbee-os` est un pack system XBee commun à Docker et VirtualBox, basé sur LFS
13.0. Il référence l'image conteneur `xbee-os:13.0` et le VMDK publié dans la
release `v0.3.3`.
Les paquets proviennent du dépôt signé XBee et sont installés par `xbpkg`.
L'image conteneur n'embarque ni noyau, ni GRUB, ni serveur SSH. Elle contient
les bibliothèques et outils utilisateur de systemd requis par `su`, mais
systemd n'est pas utilisé comme processus d'initialisation du conteneur.

## Utiliser le pack system

```bash
cd native/xbee-os
xbee validate
xbee enter --system .
```

L'archive Docker distribuable est construite par `../xbee-os-image` :

```bash
xbee builder build ../xbee-os-image
```

Le builder `xbee-os-image` produit sous `/opt/xbee-os` :

- `xbee-os-13.0-docker.tar.zst`, chargeable directement par Docker ;
- `xbee-os-13.0-rootfs.tar.zst`, utilisable par les autres runtimes OCI ;
- `packages.txt`, `metadata.yaml` et `SHA256SUMS`.

## Charger et utiliser l'image

```bash
docker load --input xbee-os-13.0-docker.tar.zst
docker run --rm -it xbee-os:13.0
xbpkg list
```

## Utiliser le même système avec VirtualBox

```bash
cd ../virtualbox-xbee-os
xbee pack
xbee up
xbee enter
```

Le provider VirtualBox sélectionne automatiquement le VMDK déclaré dans le
pack system, tandis que le provider conteneur utilise `xbee-os:13.0`.

Pour configurer un dépôt distant, créer un fichier dans
`/etc/xbpkg/repositories.d/`. Le certificat du dépôt utilisé pour construire
l'image est déjà installé dans `/etc/xbpkg/trusted-keys/`.
