# BLFS package template (`lfs/native/package-blfs-template`)

Ce dossier est un **squelette** pour créer un package BLFS au format XBee (`xbpkg`).

## Utilisation

1. Copier ce répertoire en `lfs/native/package-<nom-du-paquet>` (ex. `package-blfs-tmux`).
2. Renseigner `xbee-pack-builder.yaml` :
   - `package.name`
   - `package.version`
   - `package.source`
   - `package.runtime-dependencies`
3. Remplacer le contenu de `resources/build-blfs-xbpkg.sh` par la recette réelle du
   package (configure/make/make install, création des hooks éventuels, etc.).
4. Ajouter la source correspondante dans la chaîne BLFS de `final-sources` (par défaut,
   le template attend un archive déjà présent dans `final-rootfs`/`sources`).
5. Ajouter ensuite ce builder dans:
   - `lfs/native/package-repository/xbee-pack-builder.yaml` (section `builder`)
   - et, si besoin, dans les profils concernés.

## Exemple de nommage conseillé

- `package-blfs-tmux`
- `package-blfs-nginx`
- `package-blfs-cmake`

Le nom logique du package dans les métadonnées XBee reste celui défini dans
`package.name`.
