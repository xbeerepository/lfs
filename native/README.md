# Début de l'approche LFS native

Cette filière porte les commandes des chapitres 5 à 8 du livre LFS 13.0 dans
des builders XBee natifs.

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
final-system ----------------> package-{glibc,...,rsync}
   |                                      |
   v                                      v
bootable-system                    package-repository
                                          |
                                          v
                                    package-system
                                      /           \
                                     v             v
                                  full          minimal
                                     |
                                     v
                            package-uefi-system
                                          |
                                          v
                                package-release-system
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

L'agent minimal `nocloud-agent` est un artefact partagé : `cloud-image` et
`package-system` installent donc le même script de provisionnement, contrôlé
par une somme SHA-256, au lieu d'en maintenir deux copies.

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
13.0. Le builder `final-sources` l'enrichit ensuite avec les 70 fichiers du
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
existantes avec les 70 sources additionnelles.

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
/opt/xbee-lfs-native/xbee-lfs-native-13.0-x86_64-virtualbox.vmdk
/opt/xbee-lfs-native/xbee-lfs-native-13.0-x86_64-virtualbox.vmdk.sha256
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
Lorsqu'ils sont présents dans l'image, le smoke test contrôle aussi le noyau
et ses modules granulaires, dhcpcd, curl, Wget et rsync.

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
chapitre 8. Quatre-vingt-onze builders recompilent séparément Glibc, Zlib, Bzip2, XZ, Zstd, LZ4,
Attr, Acl, Libpipeline, Man-DB, Ncurses, Readline, PCRE2, Libcap, Libelf, GMP,
MPFR, MPC, M4, Bison, Flex, Autoconf, Automake, Libtool et Pkgconf à partir du
rootfs final. Binutils, GCC, Libffi, Expat, GDBM, OpenSSL, SQLite et Python
complètent cette chaîne, avec Flit-core, Packaging, MarkupSafe, Jinja2, Meson
et Ninja. BC, Gperf, Libxcrypt, Less, Kmod et Procps-ng ajoutent les outils
système fondamentaux. E2fsprogs, Shadow, Iproute2, Inetutils, Kbd et Psmisc
complètent les outils d'administration. Man-pages, Iana-Etc et File fournissent
la documentation et les bases système, tandis que Tcl, Expect et DejaGnu
ajoutent la chaîne de tests. Sed, Gettext, Grep et Bash complètent les outils
texte et le shell, puis Perl et XML::Parser fournissent leur chaîne de modules.
Intltool complète cette chaîne, Wheel et Setuptools étendent l'environnement
Python, puis Coreutils, Diffutils et Gawk ajoutent les utilitaires GNU centraux.
Findutils, Groff, Gzip, Make, Patch et Tar complètent les outils de recherche,
de documentation, de construction et d'archivage. Texinfo, Vim, D-Bus,
Util-linux, Systemd et GRUB terminent les outils du système et de l'amorçage.
Linux Headers, Linux Kernel et Linux Modules fournissent le noyau installable,
puis OpenSSH et Sudo ajoutent l'accès distant et l'administration privilégiée.
CA Certificates, Wget, curl, dhcpcd et rsync complètent la pile réseau,
le téléchargement sécurisé et la synchronisation de fichiers.

Chaque paquet déclare ses dépendances de construction sous l'élément XBee
standard `builder`. XBee construit ces paquets en premier et expose leurs
archives dans `/opt/xbee-lfs-packages`. Avant d'entrer dans le chroot, le
builder du paquet vérifie chaque archive et superpose son payload au
`final-system` utilisé comme système de bootstrap. La compilation consomme
donc réellement les artefacts déclarés, et pas leurs anciennes copies du
rootfs monolithique.

`runtime-dependencies` reste distinct : cette variable est uniquement
transcrite en `dependencies` dans le manifeste destiné à `xbpkg`. Une
dépendance de construction et une dépendance d'exécution peuvent ainsi
évoluer indépendamment.

Tous produisent des archives immuables :

```text
NAME-VERSION-x86_64.xbpkg.tar.zst
```

Chaque archive contient un manifeste, la liste des chemins, les sommes
SHA-256 des fichiers ordinaires et un payload `rootfs/`. Le builder
`package-repository` réunit les quatre-vingt-onze paquets et `xbpkg`, puis teste
l'installation, la liste, la recherche du propriétaire, la vérification,
la mise à niveau, la suppression et le refus des collisions :

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
xbpkg --root /tmp/lfs-test upgrade zlib-1.3.3-x86_64.xbpkg.tar.zst
xbpkg --root /tmp/lfs-test verify zlib
xbpkg --root /tmp/lfs-test check
xbpkg --root /tmp/lfs-test recover
xbpkg --root /tmp/lfs-test owner /usr/lib/libz.so.1.3.2
xbpkg --root /tmp/lfs-test remove zlib
```

### Dépôts configurés et action XBee `pkg`

Depuis `xbpkg` 0.18.0, les dépôts sont découverts dans
`/etc/xbpkg/repositories.d/*.conf`. Un dépôt peut être local :

```yaml
schema-version: 1
name: local
location: "file:///opt/xbee-lfs-repository"
enabled: true
key: "/etc/xbpkg/trusted-keys/local.pem"
```

ou distant via HTTP(S). `xbpkg refresh` télécharge alors le manifeste signé et
les archives dans `/var/cache/xbpkg/repositories/`, vérifie la signature
Ed25519 et toutes les sommes SHA-256, puis remplace atomiquement le cache.

Sur un système dont `/etc/os-release` contient `ID=xbee-lfs`, l'action XBee
`pkg` sélectionne automatiquement ce gestionnaire :

```yaml
provision:
  - gpg:
      name: xbee-lfs
      from: https://example.com/xbee-lfs-repository.pem
      fingerprint: "SHA256_DE_LA_CLE_DER"
  - repo:
      name: xbee-lfs
      location: https://example.com/lfs/13.0/x86_64
      gpg: xbee-lfs
  - pkg:
      name:
        - curl
        - openssh
      update: true
```

Pour `xbpkg`, l'action générique `gpg` installe en réalité une clé publique PEM
OpenSSL et contrôle l'empreinte SHA-256 de sa représentation DER. Les modes
`group` et `builddep` ne sont pas pris en charge.

Avec un dépôt, un nom de paquet suffit :

```bash
xbpkg \
  --root /tmp/lfs-test \
  --repository /opt/xbee-lfs-repository \
  --trusted-key /etc/xbpkg/trusted-repository-key.pem \
  --dry-run \
  install curl
xbpkg \
  --root /tmp/lfs-test \
  --repository /opt/xbee-lfs-repository \
  --trusted-key /etc/xbpkg/trusted-repository-key.pem \
  install curl
xbpkg \
  --root /tmp/lfs-test \
  --repository /opt/xbee-lfs-repository \
  --trusted-key /etc/xbpkg/trusted-repository-key.pem \
  --dry-run \
  update
xbpkg \
  --root /tmp/lfs-test \
  --repository /opt/xbee-lfs-repository \
  --trusted-key /etc/xbpkg/trusted-repository-key.pem \
  update
```

Le gestionnaire sélectionne la version la plus récente présente dans
`packages/`, vérifie la signature Ed25519 de `SHA256SUMS` puis l'entrée de
chaque archive, et parcourt récursivement les
manifestes et construit un plan ordonné. `--dry-run` affiche ce plan sans
modifier la racine. Avant l'installation réelle, toutes les archives, sommes
du payload et collisions sont contrôlées. Une dépendance commune n'est
installée qu'une fois ; les dépendances absentes et les cycles sont refusés.
Si l'exécution échoue malgré ces contrôles, les nouveaux fichiers et les
entrées de base créés par le plan sont restaurés. `XBPKG_REPOSITORY` fournit
la même configuration que l'option `--repository`.

Les dépendances acceptent un nom simple ou une contrainte avec `=`, `>=`, `>`,
`<=` ou `<`, par exemple `openssl >= 3.6.0`. Le résolveur choisit la version la
plus récente admissible et refuse les contraintes transitives incompatibles
avant la transaction. L'installation directe, `upgrade` et `check` appliquent
les mêmes règles ; une mise à niveau qui casserait la contrainte d'un paquet
déjà installé est refusée.

Une ou plusieurs clés de confiance peuvent être données avec des options
`--trusted-key` répétées, `XBPKG_TRUSTED_KEY` (liste séparée par `:`), ou un
répertoire `--trusted-keyring`. Par défaut, `xbpkg` consulte
`/etc/xbpkg/trusted-keys/` et conserve la compatibilité avec
`/etc/xbpkg/trusted-repository-key.pem` sous la racine cible. La clé publique
publiée avec le dépôt est informative : elle doit être distribuée ou épinglée
par un canal de confiance distinct. Un dépôt sans signature est refusé par
défaut ; `--allow-unsigned` l'autorise explicitement pour le développement
local, mais ne contourne jamais une signature présente et invalide.

`SHA256SUMS.keyid` identifie la clé signataire par le SHA-256 de sa
représentation publique DER. Une rotation consiste à installer l'ancienne et
la nouvelle clé dans le trousseau pendant la transition, puis à signer les
nouveaux dépôts avec la nouvelle. `--revoked-keys` ou
`XBPKG_REVOKED_KEYS` désigne une liste locale d'identifiants révoqués ;
`/etc/xbpkg/revoked-keys` est utilisée par défaut. Une clé révoquée est refusée
même si elle reste présente dans le trousseau.

Chaque dépôt contient également un manifeste signé `RELEASE` avec un
identifiant stable et un numéro de série croissant. Après une installation
réussie, `xbpkg` mémorise le numéro et la somme du manifeste sous
`/var/lib/xbpkg/repositories/`. Un numéro inférieur est refusé, tout comme la
réutilisation d'un même numéro avec un contenu différent. `--allow-downgrade`
autorise ponctuellement un numéro inférieur, mais ne permet jamais de
réutiliser un numéro avec un autre contenu.

Les manifestes signés `RELEASE` et `ARTIFACTS.release` contiennent également
`published-at` et `expires-at` au format UTC RFC 3339. Une publication située
à plus de vingt-quatre heures dans le futur ou déjà expirée est refusée.
`--ignore-expiration` constitue une dérogation hors ligne explicite ; elle ne
désactive ni signature, ni révocation, ni protection anti-downgrade.

Une politique `TRUST-ROOT` peut déléguer les rôles dépôt, publication et
révocation depuis plusieurs clés racines publiques épinglées. Elle possède sa
propre version anti-downgrade, une expiration et un seuil de signatures.
`xbpkg trust` vérifie la politique active ; `xbpkg trust accept` mémorise sa
version après vérification sous verrou.

La politique est construite sans stocker les clés privées dans le projet :

```bash
XBPKG_ROOT_SIGNING_KEYS=/media/key1.pem:/media/key2.pem:/media/key3.pem \
XBPKG_ROOT_THRESHOLD=2 \
build-trust-root.sh trust-output 1 2027-08-01T00:00:00Z \
  REPOSITORY_KEY_IDS RELEASE_KEY_IDS REVOCATION_KEY_IDS
```

Le résultat contient uniquement `TRUST-ROOT`, ses signatures détachées et les
clés publiques racines. Les clés privées doivent rester sur des supports
hors ligne distincts.

Les opérations qui modifient une racine (`install`, `upgrade`, `update` et
`remove`)
sont sérialisées par `var/lib/xbpkg/lock`. Une seconde opération sur la même
racine est refusée immédiatement ; les consultations et `--dry-run` restent
disponibles pendant une installation.

`check` audite l'ensemble de la base installée : identité et métadonnées des
paquets, dépendances et cycles, propriété unique des chemins, présence des
payloads et sommes SHA-256. Les configurations modifiées, manquantes ou
accompagnées d'un `.xbpkg-new` sont signalées comme états administratifs sans
faire échouer l'audit ; une incohérence de paquet produit un échec.

Après une suppression ou le rollback d'un plan, `xbpkg` retire aussi les
répertoires parents devenus vides. Le nettoyage repose sur `rmdir` : un
répertoire partagé ou contenant un fichier non géré est conservé. La remontée
s'arrête avant les répertoires de premier niveau de la racine (`/usr`, `/etc`,
`/var`, `/opt`, etc.).

Les installations résolues et les mises à jour globales écrivent avant toute
modification un journal persistant sous
`var/lib/xbpkg/transactions/current`, puis synchronisent son état après chaque
paquet. `update` compare tous les paquets installés au dépôt, valide les
contraintes du système candidat et ordonne les mises à niveau par dépendances.
Il sauvegarde les anciens payloads et métadonnées avant le premier changement :
un échec restaure donc toutes les versions précédentes. Le numéro de série du
dépôt n'est mémorisé qu'après le commit. Si le processus est interrompu
brutalement, `check` signale le journal et les nouvelles mutations sont
bloquées. `recover` annule une transaction `prepared` ou finalise une
transaction déjà marquée `committed`.

Le gestionnaire vérifie les dépendances directes à l'installation et empêche
la suppression d'un paquet encore requis. L'installation par archive directe
ne résout pas les dépendances ; l'installation depuis un dépôt résout les
dépendances transitives. Aucun script de pré/post-installation n'est exécuté.
`upgrade` exige un paquet déjà installé du même nom et d'une version différente.
Il contrôle entièrement l'archive et ses collisions avant de modifier la
racine, retire les anciens chemins, installe le nouveau payload puis remplace
les métadonnées. Les fichiers ordinaires sous `/etc` sont déclarés dans
`.XBPKG/conffiles`. Une configuration intacte est mise à niveau normalement ;
une configuration modifiée localement est conservée et la nouvelle version est
écrite avec le suffixe `.xbpkg-new`. Un nouvel upgrade est refusé tant que ce
fichier n'a pas été traité. La suppression d'un paquet conserve également ses
configurations modifiées.

## 13. Image assemblée depuis les paquets

L'assembleur partagé `package-system-tools` accepte un profil de paquets
racines. `profiles/full.txt` conserve l'image historique de 91 paquets, tandis
que `profiles/minimal.txt` laisse `xbpkg` résoudre une base amorçable et
administrable de 44 paquets. Les deux profils utilisent exactement le même
script de partitionnement, de configuration et d'installation.

Le profil minimal conserve `wget` pour amorcer les dépôts HTTP et
`e2fsprogs` pour l'agrandissement NoCloud du système de fichiers ainsi
qu'`inetutils` pour appliquer le hostname et `kbd` pour initialiser la
console virtuelle, mais exclut
volontairement `curl` et GCC. `xbpkg refresh` utilise `curl` lorsqu'il est
présent et se replie sur `wget`, ce qui permet ensuite d'installer `curl` avec
l'action XBee `pkg`.

```bash
cd native/package-minimal-system
xbee validate
xbee build
```

Artefacts minimaux :

```text
/opt/xbee-lfs-native/xbee-lfs-native-13.0-x86_64-minimal.qcow2
/opt/xbee-lfs-native/xbee-lfs-native-13.0-x86_64-minimal.qcow2.sha256
/opt/xbee-lfs-native/minimal-rootfs.tar.zst
/opt/xbee-lfs-native/minimal-system-metadata.yaml
```

Le profil complet de `package-system` crée une racine vide, installe les 91 paquets
dans l'ordre de leurs dépendances, ajoute la configuration système minimale et
produit une image BIOS amorçable. L'image contient également `xbpkg`, les
métadonnées des paquets installés, OpenSSH, sudo, un réseau DHCP et l'agent
NoCloud partagé `xbee-nocloud` :

```bash
cd native/package-system
xbee validate
xbee build \
  --var lfs.hostname=xbee-lfs \
  --var lfs.admin_user=xbee
```

Artefacts :

```text
/opt/xbee-lfs-native/package-rootfs.tar.zst
/opt/xbee-lfs-native/package-rootfs.tar.zst.sha256
/opt/xbee-lfs-native/xbee-lfs-native-13.0-x86_64-packages.qcow2
/opt/xbee-lfs-native/xbee-lfs-native-13.0-x86_64-packages.qcow2.sha256
/opt/xbee-lfs-native/package-system-metadata.yaml
```

Le compte root reste verrouillé. Par défaut, aucune clé n'est incorporée :
l'accès SSH est ouvert au premier démarrage par une seed NoCloud `cidata`
contenant `ssh_authorized_keys` ou `public-keys`. `local-hostname` configure le
nom de machine et l'agent marque la fin du provisionnement dans
`/var/lib/cloud/instance/boot-finished`. `lfs.authorized_key` reste disponible
pour les diagnostics sans seed, mais ne doit pas être utilisé pour une image
générique. Pour démarrer l'image manuellement :

```bash
qemu-system-x86_64 \
  -m 2048 \
  -drive file=xbee-lfs-native-13.0-x86_64-packages.qcow2,if=virtio \
  -nic user,hostfwd=tcp::2222-:22 \
  -nographic
```

Après connexion, `sudo xbpkg list` doit afficher 91 paquets. Ce chemin valide
que l'image peut être reproduite depuis le dépôt de paquets, indépendamment du
rootfs monolithique de `final-system`.

Le smoke test génère une seed depuis la clé privée indiquée, puis automatise
NoCloud, le démarrage QEMU, SSH, systemd, le réseau, sudo, HTTPS, rsync et les
modules du noyau. Il contrôle les 91 enregistrements de la base `xbpkg` et
vérifie l'intégrité d'un ensemble de paquets critiques :

```bash
XBEELFS_HOSTNAME=xbee-lfs \
native/package-system/resources/smoke-test.sh \
  xbee-lfs-native-13.0-x86_64-packages.qcow2 \
  ~/.ssh/id_ed25519 bios
```

## 14. Image UEFI assemblée depuis les paquets

`package-uefi-system` reprend le rootfs généré par `package-system`, remplace
la table MBR par une table GPT, crée une partition système EFI FAT32 et
installe GRUB x86_64-efi en mode amovible :

```bash
cd native/package-uefi-system
xbee validate
xbee build \
  --var packages.lfs.hostname=xbee-lfs
```

Artefacts :

```text
/opt/xbee-lfs-native/package-uefi-rootfs.tar.zst
/opt/xbee-lfs-native/package-uefi-rootfs.tar.zst.sha256
/opt/xbee-lfs-native/xbee-lfs-native-13.0-x86_64-packages-uefi.qcow2
/opt/xbee-lfs-native/xbee-lfs-native-13.0-x86_64-packages-uefi.qcow2.sha256
/opt/xbee-lfs-native/package-uefi-system-metadata.yaml
```

Le même smoke test utilise OVMF lorsque le troisième argument vaut `uefi` :

```bash
XBEELFS_HOSTNAME=xbee-lfs \
native/package-system/resources/smoke-test.sh \
  xbee-lfs-native-13.0-x86_64-packages-uefi.qcow2 \
  ~/.ssh/id_ed25519 uefi
```

## 15. Release des images assemblées depuis les paquets

`package-release-system` vérifie les images BIOS et UEFI ainsi que leurs
métadonnées, puis les regroupe dans une archive reproductible avec un manifeste
SHA-256 et une seed NoCloud sans secret. Il signe également un manifeste
externe `ARTIFACTS` avec une clé Ed25519 de publication distincte :

```bash
cd native/package-release-system
xbee validate
xbee build
```

Artefacts :

```text
/opt/xbee-lfs-native/xbee-lfs-native-13.0-x86_64-packages-release.tar.zst
/opt/xbee-lfs-native/xbee-lfs-native-13.0-x86_64-packages-release.tar.zst.sha256
/opt/xbee-lfs-native/package-release-metadata.yaml
/opt/xbee-lfs-native/ARTIFACTS
/opt/xbee-lfs-native/ARTIFACTS.sig
/opt/xbee-lfs-native/ARTIFACTS.keyid
/opt/xbee-lfs-native/release-ed25519-public.pem
/opt/xbee-lfs-native/verify-release.sh
```

Avant extraction ou écriture sur disque, la clé publique doit être obtenue par
un canal distinct puis épinglée :

```bash
./verify-release.sh . /chemin/vers/release-ed25519-public.pem
```

Le vérificateur contrôle la signature, l'identifiant et la révocation de la
clé, les tailles, les sommes SHA-256, les fichiers manquants et les fichiers
inattendus. Après extraction, `sha256sum -c SHA256SUMS` contrôle les images, les
métadonnées, la documentation et les modèles NoCloud. Il faut remplacer
`YOUR_SSH_PUBLIC_KEY` dans `nocloud-seed/user-data` avant de créer `seed.iso`.

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
