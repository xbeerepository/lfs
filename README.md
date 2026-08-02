# Construire Linux From Scratch avec XBee

Ce prototype construit une distribution LFS systemd en deux builders XBee :

```text
rootfs (jhalfs + noyau)
  |
  v
image (MBR/EXT4/GRUB + QCOW2)
```

Cette racine contient deux implémentations :

- `rootfs` puis `image` : approche rapide fondée sur jhalfs ;
- [`native`](native/README.md) : approche native découpée en `sources`,
  `cross-toolchain`, `temporary-system`, `chroot-system`, `final-system` et
  `bootable-system`, `provisioned-system`, `cloud-image`, `uefi-system`, puis
  `release-system`. Les packs `system-rootfs` et `lfs-system` rendent aussi le
  rootfs LFS utilisable comme système d'exécution XBee. Une couche de 91
  paquets immuables fournit `xbpkg`; `package-system` réassemble directement
  ces paquets en une image BIOS amorçable et `package-uefi-system` en dérive
  une variante GPT/UEFI, sans réutiliser le rootfs final monolithique. Les deux
  utilisent l'agent NoCloud partagé pour provisionner le hostname et la clé SSH
  au premier démarrage. `package-release-system` publie les deux formats avec
  leurs métadonnées et un manifeste SHA-256 reproductible.

## Prérequis

- Linux `x86_64` ;
- Docker fonctionnel ;
- au moins 40 Gio d'espace libre ;
- 8 Gio de mémoire recommandés ;
- accès Internet pour Git, l'image `ubuntu:24.04` et les sources LFS.

Le system pack local `build-system` rend l'exemple indépendant d'un registre
de packs XBee.

Le build complet compile tout LFS et dure généralement plusieurs heures.

## Construire le root filesystem

```bash
cd rootfs
xbee show model
xbee build
```

Paramètres principaux :

```bash
xbee build \
  --var lfs.book=13.0 \
  --var lfs.jobs=8 \
  --var lfs.run-tests=false
```

Le builder exporte :

```text
/opt/xbee-lfs/rootfs.tar.zst
/opt/xbee-lfs/rootfs.tar.zst.sha256
/opt/xbee-lfs/build-metadata.yaml
```

## Construire l'image QCOW2

Le builder `image` référence automatiquement le builder `rootfs`.

```bash
cd image
xbee show build
xbee build
```

Il exporte :

```text
/opt/xbee-lfs/xbee-lfs-13.0-x86_64.qcow2
/opt/xbee-lfs/xbee-lfs-13.0-x86_64.qcow2.sha256
/opt/xbee-lfs/image-metadata.yaml
```

Pour personnaliser le nom et l'espace libre :

```bash
xbee build \
  --var image.name=mon-lfs \
  --var image.extra-size-mib=4096
```

Les variables du builder `rootfs` peuvent être transmises depuis `image` avec
son alias :

```bash
xbee build \
  --var rootfs.lfs.book=13.0 \
  --var rootfs.lfs.jobs=8 \
  --var image.name=mon-lfs-13.0
```

## Tester avec QEMU

Après extraction de l'artefact builder :

```bash
qemu-system-x86_64 \
  -enable-kvm \
  -m 4096 \
  -drive file=xbee-lfs-13.0-x86_64.qcow2,if=virtio \
  -nic user \
  -nographic
```

Le noyau écrit sa console sur `ttyS0`. Le prototype ne définit volontairement
aucun mot de passe et n'installe pas SSH. La première validation attendue est
donc un démarrage jusqu'à l'invite locale systemd.

## Limites de l'approche jhalfs

- cible `x86_64` uniquement ;
- BIOS/GRUB uniquement pour cette filière rapide ;
- réseau statique généré par jhalfs ;
- absence de création d'utilisateur final et de politique de mot de passe ;
- compilation intégrale à chaque changement qui invalide le builder rootfs ;
- les sources sont mises en cache par jhalfs dans le conteneur de build, pas
  encore exportées comme un builder XBee distinct.

Le builder utilise jhalfs afin de rester aligné avec les commandes extraites du
livre officiel. Une évolution ultérieure pourra séparer `sources`,
`cross-toolchain`, `temporary-system` et `base-rootfs` en artefacts XBee.

## Licence

Le code de ce dépôt est distribué sous licence
[Apache-2.0](LICENSE). Les composants téléchargés et intégrés à l'image LFS
restent soumis à leurs licences respectives.

## Utiliser LFS comme system pack

Le descripteur [`xbee-pack-system.yaml`](xbee-pack-system.yaml) expose LFS 13.0
comme distribution XBee. Pour VirtualBox, il sélectionne l'image VMDK publiée
avec la release, désactive les Guest Additions spécifiques aux distributions
à base de paquets et utilise le provisionnement NoCloud intégré à LFS.

## Exécuter LFS avec Docker

L'exemple [`examples/docker`](examples/docker/README.md) construit le root
filesystem LFS natif puis l'exécute avec le provider Docker interne de XBee.
Il fournit un environnement léger pour valider l'espace utilisateur LFS, sans
démarrer le noyau ni l'image disque LFS.

L'exemple
[`examples/xbpkg-virtualbox`](examples/xbpkg-virtualbox/README.md) démarre
l'image minimale dans VirtualBox et valide la chaîne d'actions XBee
`gpg` → `repo` → `pkg` en installant réellement `curl`.
