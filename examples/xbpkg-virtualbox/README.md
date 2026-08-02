# Action XBee `pkg` avec `xbpkg`

Cet environnement démarre l'image LFS minimale dans VirtualBox et exécute la
chaîne XBee standard `gpg` → `repo` → `pkg`. Le paquet `curl`, absent de
l'image initiale, est téléchargé depuis un dépôt HTTP signé puis vérifié.

Le script de smoke test prépare automatiquement le VMDK et le dépôt à partir
des artefacts de builders locaux. Il détecte l'adresse IPv4 de l'hôte, rend
une copie temporaire du pack, construit l'image VirtualBox finale et valide
le cycle complet de l'environnement :

```bash
./smoke-test.sh
```

Il exécute successivement `xbee up`, les contrôles `xbpkg` via `xbee enter`,
puis `xbee delete`. Pour limiter le test à la construction de l'image :

```bash
XBEE_LFS_TEST_LIFECYCLE=false ./smoke-test.sh
```

Dans le pack d'exemple, `XBEE_REPOSITORY_HOST` est un marqueur à remplacer par
une adresse de l'hôte joignable depuis la VM lorsqu'il est utilisé sans le
script.

Le test nécessite XBee, VirtualBox, Python 3 et les artefacts construits
par `native/package-minimal-system` et `native/package-repository`. Il arrête
et supprime l'environnement à la fin du test, y compris en cas d'échec.

Pour examiner le modèle sans démarrer de VM :

```bash
xbee validate
xbee show model
```
