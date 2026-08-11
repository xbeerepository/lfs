# Construire Linux From Scratch avec XBee

Ce projet construit nativement une distribution LFS 13.0 systemd. Les
commandes des chapitres 3 à 10 du livre sont organisées en builders XBee et en
artefacts intermédiaires vérifiables.

```text
sources → cross-toolchain → temporary-system → chroot-system → final-system
                                                               |
                                                               v
                                                     paquets xbpkg
                                                               |
                                                               v
                                                images BIOS et UEFI
                                                               |
                                                               v
                                                     release signée
```

La documentation complète de la construction, des artefacts et des tests se
trouve dans [`native/README.md`](native/README.md). La signature des dépôts et
des releases est détaillée dans
[`ARTIFACT-SIGNING.md`](ARTIFACT-SIGNING.md).

## Prérequis

- Linux `x86_64` ;
- Docker fonctionnel ;
- au moins 40 Gio d'espace libre ;
- 8 Gio de mémoire recommandés ;
- accès Internet pour l'image `ubuntu:24.04` et les sources LFS.

Le system pack local `build-system` rend l'exemple indépendant d'un registre
de packs XBee.

Le build complet compile LFS et ses 446 paquets, puis assemble les images. Il
dure généralement plusieurs heures.

## Construire la release complète

Le dernier builder reconstruit automatiquement toute dépendance absente :

```bash
cd native/package-release-system
xbee validate
xbee show build
xbee build
```

Les principaux artefacts sont :

```text
/opt/xbee-lfs-native/xbee-lfs-native-13.0-x86_64-packages-release.tar.zst
/opt/xbee-lfs-native/xbee-lfs-native-13.0-x86_64-packages-release.tar.zst.sha256
/opt/xbee-lfs-native/ARTIFACTS
/opt/xbee-lfs-native/ARTIFACTS.sig
/opt/xbee-lfs-native/ARTIFACTS.keyid
/opt/xbee-lfs-native/release-ed25519-public.pem
/opt/xbee-lfs-native/verify-release.sh
```

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
