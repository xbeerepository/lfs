# XBee OS

`xbee-os` est un pack system XBee basé sur une distribution conteneur minimale
LFS 13.0.
Les paquets proviennent du dépôt signé XBee et sont installés par `xbpkg`.
L'image n'embarque ni noyau, ni GRUB, ni systemd, ni serveur SSH : ces
composants sont fournis par l'hôte Docker et sont inutiles dans un conteneur.

## Utiliser le pack system

```bash
cd native/xbee-os
xbee validate
xbee --system . enter
```

La racine du système est construite par `../xbee-os-rootfs`. L'archive Docker
distribuable est construite séparément par `../xbee-os-image` :

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

Pour configurer un dépôt distant, créer un fichier dans
`/etc/xbpkg/repositories.d/`. Le certificat du dépôt utilisé pour construire
l'image est déjà installé dans `/etc/xbpkg/trusted-keys/`.
