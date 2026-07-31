# Début de l'approche LFS native

Cette filière n'utilise pas jhalfs pour exécuter la construction. Les commandes
des chapitres 5 à 8 du livre LFS 13.0 sont portées dans des builders XBee.

```text
sources
   |
   v
cross-toolchain
   |
   v
temporary-system
   |
   v
chroot-system
   |
   +-------------------+
                       |
sources --> final-sources
                       |
   +-------------------+
   |
   v
final-system ----------------> package-{zlib,bzip2,xz,zstd}
   |                                      |
   v                                      v
bootable-system                    package-repository
   |
   v
provisioned-system
   |
   v
cloud-image
   |
   +--------------------+
   |                    |
   v                    v
uefi-system       system-rootfs <--- package-manager
   |                    |
   v                    v
release-system      lfs-system
```

Les scripts restent volontairement proches du livre pour faciliter leur
comparaison avec la référence officielle :

- chapitre 3 : acquisition et contrôle des sources ;
- chapitre 5 : Binutils pass 1, GCC pass 1, headers Linux, Glibc et Libstdc++ ;
- chapitre 6 : outils temporaires, Binutils pass 2 et GCC pass 2.
- chapitre 7 : préparation du chroot et outils temporaires additionnels.
- chapitre 8 : construction des logiciels définitifs du système ;
- chapitres 9 et 10 : configuration, noyau Linux et image amorçable.

## Prérequis

- hôte Linux `x86_64` ;
- Docker fonctionnel ;
- 40 Gio d'espace libre au minimum ;
- 8 Gio de mémoire recommandés ;
- accès Internet pour le builder `sources`.

Les builders de compilation n'accèdent pas au réseau. Ils consomment
uniquement l'artefact vérifié du premier builder.

## 1. Sources

```bash
cd native/sources
xbee validate
xbee show model
xbee build
```

Artefacts :

```text
/opt/xbee-lfs-native/sources/
/opt/xbee-lfs-native/sources/MD5SUMS
/opt/xbee-lfs-native/sources-metadata.yaml
```

Le manifeste contient les 29 archives et patches nécessaires aux chapitres 5
à 7. Chaque fichier est vérifié avec la somme MD5 publiée dans le livre LFS
13.0. Le builder `final-sources` l'enrichit ensuite avec les 63 fichiers du
chapitre 8, sans invalider les étapes déjà construites.

## 2. Cross-toolchain

Le builder construit automatiquement `sources` si son artefact n'est pas
présent :

```bash
cd native/cross-toolchain
xbee validate
xbee show build
xbee build --var lfs.jobs=8
```

Artefacts :

```text
/opt/xbee-lfs-native/cross-rootfs.tar.zst
/opt/xbee-lfs-native/cross-rootfs.tar.zst.sha256
/opt/xbee-lfs-native/cross-metadata.yaml
```

Le rootfs contient `/tools`, les headers Linux et la bibliothèque C cible. Les
sources et répertoires de compilation sont exclus de l'archive.

## 3. Système temporaire

Cette commande construit toute la chaîne manquante, puis les outils du chapitre
6 :

```bash
cd native/temporary-system
xbee validate
xbee show build
xbee build \
  --var cross.lfs.jobs=8 \
  --var lfs.jobs=8
```

Artefacts :

```text
/opt/xbee-lfs-native/temporary-rootfs.tar.zst
/opt/xbee-lfs-native/temporary-rootfs.tar.zst.sha256
/opt/xbee-lfs-native/temporary-metadata.yaml
```

`cross.lfs.jobs` configure le builder `cross-toolchain`; `lfs.jobs` configure le
builder courant. Les deux valeurs font partie des identités fonctionnelles des
artefacts XBee.

## 4. Système chroot

Le quatrième builder prépare les fichiers essentiels du système, entre dans le
chroot et construit les outils temporaires additionnels du chapitre 7 :

```bash
cd native/chroot-system
xbee validate
xbee show build
xbee build \
  --var temporary.cross.lfs.jobs=8 \
  --var temporary.lfs.jobs=8 \
  --var lfs.jobs=8
```

Artefacts :

```text
/opt/xbee-lfs-native/chroot-rootfs.tar.zst
/opt/xbee-lfs-native/chroot-rootfs.tar.zst.sha256
/opt/xbee-lfs-native/chroot-metadata.yaml
```

Le builder installe Gettext, Bison, Perl, Python, Texinfo et Util-linux, puis
supprime `/tools`. Le résultat est le point de reprise prévu avant le chapitre
8.

## 5. Système final

Le cinquième builder compile les logiciels définitifs du chapitre 8 dans le
chroot. Les suites de tests, très longues et parfois dépendantes de
pseudo-systèmes de fichiers montés, sont omises :

`final-sources` est construit automatiquement et fusionne les 29 sources
existantes avec les 63 sources additionnelles.

```bash
cd native/final-system
xbee validate
xbee show build
xbee build \
  --var chroot.temporary.cross.lfs.jobs=8 \
  --var chroot.temporary.lfs.jobs=8 \
  --var chroot.lfs.jobs=8 \
  --var lfs.jobs=8 \
  --var lfs.timezone=Europe/Paris
```

Artefacts :

```text
/opt/xbee-lfs-native/final-rootfs.tar.zst
/opt/xbee-lfs-native/final-rootfs.tar.zst.sha256
/opt/xbee-lfs-native/final-metadata.yaml
```

Le compte `root` est volontairement verrouillé. Il devra recevoir un mot de
passe ou être remplacé par un utilisateur administrateur lors de la
configuration de l'image.

## 6. Système amorçable

Le sixième builder configure le système, compile Linux 6.18.10 avec les
pilotes VirtIO intégrés et produit une image BIOS QCOW2 :

```bash
cd native/bootable-system
xbee validate
xbee show build
xbee build \
  --var final.chroot.temporary.cross.lfs.jobs=8 \
  --var final.chroot.temporary.lfs.jobs=8 \
  --var final.chroot.lfs.jobs=8 \
  --var final.lfs.jobs=8 \
  --var lfs.jobs=8 \
  --var lfs.hostname=xbee-lfs \
  --var lfs.locale=en_US.UTF-8 \
  --var image.extra_size_mib=1024
```

Artefacts :

```text
/opt/xbee-lfs-native/bootable-rootfs.tar.zst
/opt/xbee-lfs-native/bootable-rootfs.tar.zst.sha256
/opt/xbee-lfs-native/xbee-lfs-native-13.0-x86_64.qcow2
/opt/xbee-lfs-native/xbee-lfs-native-13.0-x86_64.qcow2.sha256
/opt/xbee-lfs-native/bootable-metadata.yaml
```

L'image utilise une table de partitions MBR, une partition Ext4 et GRUB BIOS.
Le réseau filaire est configuré par `systemd-networkd` en DHCP. La console
série est disponible sur `ttyS0`. Le compte `root` demeure verrouillé.

```bash
qemu-system-x86_64 \
  -m 2048 \
  -nographic \
  -drive file=xbee-lfs-native-13.0-x86_64.qcow2,if=virtio
```

## 7. Système provisionné

Le septième builder compile sudo 1.9.17p2 et OpenSSH 10.4p1 dans le rootfs,
crée l'administrateur `xbee` et produit une nouvelle image. Les mots de passe
et la connexion SSH de root sont désactivés. L'accès distant exige une clé
publique :

```bash
public_key_base64=$(base64 -w0 ~/.ssh/id_ed25519.pub)

cd native/provisioned-system
xbee validate
xbee show build
xbee build \
  --var lfs.jobs=8 \
  --var access.authorized_key_base64="$public_key_base64"
```

Artefacts :

```text
/opt/xbee-lfs-native/provisioned-rootfs.tar.zst
/opt/xbee-lfs-native/provisioned-rootfs.tar.zst.sha256
/opt/xbee-lfs-native/xbee-lfs-native-13.0-x86_64-provisioned.qcow2
/opt/xbee-lfs-native/xbee-lfs-native-13.0-x86_64-provisioned.qcow2.sha256
/opt/xbee-lfs-native/provisioned-metadata.yaml
```

Le builder accepte une clé vide pour permettre la production d'une image de
base, mais cette image ne permet alors aucune connexion. Avec QEMU :

```bash
qemu-system-x86_64 \
  -m 2048 \
  -nographic \
  -drive file=xbee-lfs-native-13.0-x86_64-provisioned.qcow2,if=virtio \
  -nic user,hostfwd=tcp::2222-:22

ssh -p 2222 xbee@127.0.0.1
sudo id
```

## 8. Image cloud NoCloud

Le huitième builder retire toute clé intégrée et installe l'agent minimal
`xbee-nocloud`. Au premier démarrage, celui-ci lit un disque ISO étiqueté
`cidata`, configure le hostname et les clés SSH, génère les clés hôte OpenSSH,
puis agrandit la partition et Ext4 si le disque virtuel a été étendu.

```bash
cd native/cloud-image
xbee validate
xbee build
```

Artefacts :

```text
/opt/xbee-lfs-native/cloud-rootfs.tar.zst
/opt/xbee-lfs-native/cloud-rootfs.tar.zst.sha256
/opt/xbee-lfs-native/xbee-lfs-native-13.0-x86_64-cloud.qcow2
/opt/xbee-lfs-native/xbee-lfs-native-13.0-x86_64-cloud.qcow2.sha256
/opt/xbee-lfs-native/cloud-metadata.yaml
```

Créer une seed NoCloud :

```bash
mkdir seed
cat >seed/meta-data <<'EOF'
instance-id: xbee-demo-001
local-hostname: xbee-cloud
EOF

cat >seed/user-data <<EOF
#cloud-config
ssh_authorized_keys:
  - $(cat ~/.ssh/id_ed25519.pub)
EOF

xorriso -as mkisofs \
  -volid cidata -joliet -rock \
  -output seed.iso seed/user-data seed/meta-data
```

Tester l'image après l'avoir éventuellement agrandie :

```bash
qemu-img resize xbee-lfs-native-13.0-x86_64-cloud.qcow2 8G
qemu-system-x86_64 \
  -m 2048 \
  -nographic \
  -drive file=xbee-lfs-native-13.0-x86_64-cloud.qcow2,if=virtio \
  -drive file=seed.iso,media=cdrom,readonly=on \
  -nic user,hostfwd=tcp::2222-:22

ssh -p 2222 xbee@127.0.0.1
```

Cette compatibilité NoCloud est volontairement limitée à `instance-id`,
`local-hostname`, `public-keys`, `hostname` et `ssh_authorized_keys`. Elle
n'exécute pas `runcmd`, `bootcmd`, des paquets ou du contenu utilisateur
arbitraire.

## 9. Image UEFI/GPT

Le neuvième builder remplace le partitionnement MBR par GPT, ajoute une
partition système EFI FAT32 de 256 Mio et installe GRUB x86_64-efi sous le
chemin de secours standard `EFI/BOOT/BOOTX64.EFI`. La racine Ext4 est la
partition 2 et conserve le provisionnement NoCloud.

```bash
cd native/uefi-system
xbee validate
xbee build
```

Artefacts :

```text
/opt/xbee-lfs-native/uefi-rootfs.tar.zst
/opt/xbee-lfs-native/uefi-rootfs.tar.zst.sha256
/opt/xbee-lfs-native/xbee-lfs-native-13.0-x86_64-uefi.qcow2
/opt/xbee-lfs-native/xbee-lfs-native-13.0-x86_64-uefi.qcow2.sha256
/opt/xbee-lfs-native/uefi-metadata.yaml
```

L'image utilise la même seed `cidata` que l'étape précédente. Pour la tester
avec OVMF :

```bash
cp /usr/share/OVMF/OVMF_VARS_4M.fd OVMF_VARS_4M.fd

qemu-system-x86_64 \
  -m 2048 \
  -nographic \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd \
  -drive if=pflash,format=raw,file=OVMF_VARS_4M.fd \
  -drive file=xbee-lfs-native-13.0-x86_64-uefi.qcow2,if=virtio \
  -drive file=seed.iso,media=cdrom,readonly=on \
  -nic user,hostfwd=tcp::2222-:22
```

## 10. Publication

Le dixième builder regroupe les images cloud BIOS et UEFI dans une archive
de distribution reproductible. Il vérifie les sommes des deux images avant
de produire le paquet et fournit une seed NoCloud sans secret :

```bash
cd native/release-system
xbee validate
xbee build
```

Artefacts :

```text
/opt/xbee-lfs-native/xbee-lfs-native-13.0-x86_64-release.tar.zst
/opt/xbee-lfs-native/xbee-lfs-native-13.0-x86_64-release.tar.zst.sha256
/opt/xbee-lfs-native/release-metadata.yaml
```

Après extraction, `SHA256SUMS` vérifie les images et métadonnées, tandis que
`README.md` décrit la création de `seed.iso`. Il faut remplacer
`YOUR_SSH_PUBLIC_KEY` dans `nocloud-seed/user-data` avant le premier
démarrage.

### Smoke test QEMU

Le script de contrôle démarre successivement les images BIOS et UEFI sur des
overlays jetables. Il injecte une clé SSH éphémère avec NoCloud, puis vérifie
le hostname, le noyau, systemd, SSH et sudo :

```bash
native/release-system/resources/smoke-test.sh \
  xbee-lfs-native-13.0-x86_64-release.tar.zst
```

Il nécessite `qemu-system-x86_64`, `qemu-img`, OVMF, `xorriso` et un client
OpenSSH. Le second argument permet de ne tester que `bios` ou `uefi`.

## 11. Pack system XBee

`system-rootfs` vérifie et exporte le rootfs cloud sous la forme attendue par
`docker import`. Le pack `lfs-system` utilise ensuite cet artefact via
`system.builder` :

```bash
cd native/lfs-system
xbee validate
```

Un autre pack local peut sélectionner ce système avec :

```yaml
require: ../lfs-system
```

Il peut aussi être choisi explicitement :

```bash
xbee --system ../lfs-system enter
```

Le système possède Bash, les outils LFS définitifs et l'utilisateur `xbee`.
Les commandes XBee s'exécutent par défaut avec `root` dans `/workspace`.
Le gestionnaire minimal `/usr/bin/xbpkg` est également installé.

## 12. Paquets granulaires

Cette première itération valide le format de paquets sans redécouper tout le
chapitre 8. Quatre builders recompilent séparément Zlib, Bzip2, XZ et Zstd à
partir du rootfs final et produisent des archives immuables :

```text
NAME-VERSION-x86_64.xbpkg.tar.zst
```

Chaque archive contient un manifeste, la liste des chemins, les sommes
SHA-256 des fichiers ordinaires et un payload `rootfs/`. Le builder
`package-repository` réunit les quatre paquets et `xbpkg`, puis teste
l'installation, la liste, la recherche du propriétaire, la vérification,
la suppression et le refus des collisions :

```bash
cd native/package-repository
xbee validate
xbee build
```

Artefacts :

```text
/opt/xbee-lfs-repository/bin/xbpkg
/opt/xbee-lfs-repository/packages/*.xbpkg.tar.zst
/opt/xbee-lfs-repository/index.yaml
/opt/xbee-lfs-repository/SHA256SUMS
```

Le gestionnaire accepte une racine alternative, ce qui permet de tester un
paquet sans modifier l'hôte :

```bash
xbpkg --root /tmp/lfs-test install zlib-1.3.2-x86_64.xbpkg.tar.zst
xbpkg --root /tmp/lfs-test verify zlib
xbpkg --root /tmp/lfs-test owner /usr/lib/libz.so.1.3.2
xbpkg --root /tmp/lfs-test remove zlib
```

Ce jalon ne résout pas encore les dépendances transitives et n'exécute pas de
scripts de pré/post-installation. Il fournit la base permettant de convertir
progressivement les autres logiciels du système final en unités de build.

## Contrôles

Chaque étape :

1. vérifie l'artefact d'entrée ;
2. compile sous l'utilisateur non privilégié `xbee-lfs-native` ;
3. vérifie la présence des binaires essentiels ;
4. produit une archive Zstandard ;
5. génère une somme SHA-256 et un manifeste YAML.

Les sources LFS sont téléchargées par les builders `sources` et
`final-sources`. Le dernier builder télécharge séparément les archives
officielles épinglées de sudo et OpenSSH. Les sources sont réextraites avant
chaque compilation pour éviter de réutiliser un arbre modifié.

## Limite de ce jalon

Les images sont amorçables sous QEMU/KVM en mode BIOS ou UEFI et possèdent un
administrateur provisionnable par seed NoCloud. Elles ne contiennent pas
encore d'initramfs ni l'ensemble des modules du projet cloud-init.

Références :

- https://www.linuxfromscratch.org/lfs/view/stable-systemd/chapter05/
- https://www.linuxfromscratch.org/lfs/view/stable-systemd/chapter06/
- https://www.linuxfromscratch.org/lfs/view/stable-systemd/chapter07/
- https://www.linuxfromscratch.org/lfs/view/stable-systemd/chapter08/
- https://www.linuxfromscratch.org/lfs/view/stable-systemd/chapter09/
- https://www.linuxfromscratch.org/lfs/view/stable-systemd/chapter10/
