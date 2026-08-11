# Signature des artefacts XBee LFS

Les artefacts XBee LFS utilisent deux niveaux de signature cryptographique :

1. la signature du dépôt de paquets `xbpkg` ;
2. la signature des artefacts de publication BIOS et UEFI.

Les deux mécanismes utilisent des clés **Ed25519** et les commandes de signature
fournies par OpenSSL.

## Dépôt de paquets `xbpkg`

Le pack
[`native/package-repository`](native/package-repository/xbee-pack-builder.yaml)
construit et signe le dépôt de paquets.

### Construction du manifeste

Le script
[`build-package-repository.sh`](native/package-repository/resources/build-package-repository.sh)
calcule les sommes SHA-256 des éléments publiés :

- les métadonnées `RELEASE` ;
- l'index `index.yaml` ;
- le gestionnaire `bin/xbpkg` ;
- les archives `packages/*.xbpkg.tar.zst`.

Ces sommes sont enregistrées dans le manifeste `SHA256SUMS`.

### Signature

Une clé privée Ed25519 est générée pendant le build :

```bash
openssl genpkey -algorithm Ed25519 \
  -out repository-signing-key.pem
```

La clé publique correspondante est exportée dans
`repository-ed25519-public.pem`. Son identifiant est le SHA-256 de sa
représentation DER et est enregistré dans `SHA256SUMS.keyid`.

Le manifeste est signé avec la clé privée :

```bash
openssl pkeyutl -sign \
  -inkey repository-signing-key.pem \
  -rawin \
  -in SHA256SUMS \
  -out SHA256SUMS.sig
```

Le dépôt publié contient notamment :

| Fichier | Rôle |
| --- | --- |
| `SHA256SUMS` | Sommes SHA-256 des éléments du dépôt |
| `SHA256SUMS.sig` | Signature Ed25519 du manifeste |
| `SHA256SUMS.keyid` | Identifiant SHA-256 de la clé signataire |
| `repository-ed25519-public.pem` | Clé publique de vérification |
| `RELEASE` | Version, numéro de série et période de validité du dépôt |

Les paquets ne sont pas signés individuellement. Leur intégrité est couverte
par leurs sommes SHA-256 enregistrées dans le manifeste signé.

### Vérification par `xbpkg`

Le gestionnaire `xbpkg` :

1. sélectionne une clé publique de confiance ;
2. vérifie son identifiant et sa révocation éventuelle ;
3. vérifie la signature Ed25519 de `SHA256SUMS` ;
4. vérifie la somme SHA-256 de chaque fichier utilisé ;
5. contrôle les métadonnées `RELEASE`, notamment leur expiration et leur numéro
   de série.

Un dépôt non signé est refusé par défaut. L'option `--allow-unsigned` permet de
l'accepter explicitement pour le développement, mais elle ne permet pas
d'accepter une signature présente et invalide.

## Artefacts de publication BIOS et UEFI

Le pack
[`native/package-release-system`](native/package-release-system/xbee-pack-builder.yaml)
publie les images BIOS et UEFI assemblées à partir des paquets.

Il utilise une clé Ed25519 distincte de la clé du dépôt.

### Manifeste externe

Le script
[`build-package-release-system.sh`](native/package-release-system/resources/build-package-release-system.sh)
crée un manifeste externe nommé `ARTIFACTS`.

Chaque ligne contient :

```text
SHA256 taille nom-du-fichier
```

Le manifeste couvre notamment :

- l'archive de publication `.tar.zst` ;
- le fichier `.tar.zst.sha256` ;
- les métadonnées de publication ;
- `ARTIFACTS.release` ;
- le script `verify-release.sh`.

L'archive contient elle-même un fichier `SHA256SUMS` couvrant les images, les
métadonnées et la seed NoCloud qu'elle embarque.

### Signature

La release est signée avec une clé privée Ed25519 persistante, conservée hors
du dépôt Git :

```bash
~/.xbee/.ssh/xbee-lfs-release-ed25519.pem
```

Le builder monte ce fichier en lecture seule dans son conteneur sous
`/run/xbee-secrets/release-signing-key.pem`. La clé privée est utilisée
uniquement par l'opération de signature ; elle n'est copiée ni dans les
sources du builder, ni dans l'artefact exporté. Le fichier doit appartenir à
l'utilisateur qui lance XBee et avoir le mode `0600`.

La clé publique persistante correspondante est conservée dans :

```bash
~/.xbee/.ssh/xbee-lfs-release-ed25519-public.pem
```

La signature détachée du manifeste est créée ainsi :

```bash
openssl pkeyutl -sign \
  -inkey release-signing-key.pem \
  -rawin \
  -in ARTIFACTS \
  -out ARTIFACTS.sig
```

Les principaux fichiers de publication sont :

| Fichier | Rôle |
| --- | --- |
| `ARTIFACTS` | Manifeste des artefacts externes |
| `ARTIFACTS.sig` | Signature Ed25519 du manifeste |
| `ARTIFACTS.keyid` | Identifiant SHA-256 de la clé signataire |
| `ARTIFACTS.release` | Dates de publication et d'expiration |
| `release-ed25519-public.pem` | Clé publique de vérification |
| `verify-release.sh` | Vérificateur autonome de la publication |

### Vérification

Le script
[`verify-release.sh`](native/package-release-system/resources/verify-release.sh)
contrôle :

- l'identifiant de la clé publique ;
- la présence éventuelle de cet identifiant dans une liste de révocation ;
- la signature Ed25519 de `ARTIFACTS` ;
- la taille et la somme SHA-256 de chaque artefact déclaré ;
- l'absence de fichiers inattendus dans la publication ;
- les dates de publication et d'expiration.

Exemple :

```bash
./verify-release.sh \
  /chemin/vers/la-publication \
  /chemin/fiable/release-ed25519-public.pem
```

Une liste de clés révoquées peut être fournie en troisième argument :

```bash
./verify-release.sh \
  /chemin/vers/la-publication \
  /chemin/fiable/release-ed25519-public.pem \
  /chemin/vers/revoked-keys
```

## Artefacts intermédiaires

Les artefacts produits par les étapes `rootfs`, `image` et plusieurs étapes
natives intermédiaires sont accompagnés de fichiers `.sha256`.

Ces fichiers permettent de détecter une corruption accidentelle, mais ne
constituent pas une signature cryptographique : un attaquant capable de
modifier l'artefact pourrait également remplacer son fichier `.sha256`.

Ces artefacts bénéficient d'une signature lorsqu'ils sont intégrés à la
publication finale couverte par `ARTIFACTS.sig`.

## Modèle de confiance actuel

La clé privée du dépôt de paquets est actuellement générée à chaque build. La
clé privée de publication BIOS/UEFI est persistante et injectée depuis
`~/.xbee/.ssh` uniquement pendant la signature. Les clés publiques
correspondantes sont livrées avec les artefacts.

Ce fonctionnement protège contre une modification des fichiers après leur
construction, à condition que la clé publique utilisée pour la vérification
ait été obtenue par un canal fiable. En revanche, télécharger la clé publique
depuis le même emplacement que les artefacts ne permet pas d'authentifier
l'identité du producteur : un attaquant pourrait remplacer à la fois les
artefacts, la signature et la clé publique.

Pour établir une chaîne de confiance durable, il est recommandé de :

1. sauvegarder la clé privée de publication persistante dans un gestionnaire
   de secrets ou un module matériel ;
2. ne jamais inclure cette clé privée dans les artefacts ou dans le dépôt Git ;
3. distribuer l'empreinte ou la clé publique par un canal indépendant ;
4. séparer la clé du dépôt de la clé de publication ;
5. prévoir une procédure documentée de rotation et de révocation des clés ;
6. injecter la clé privée dans le build uniquement pendant l'opération de
   signature.
