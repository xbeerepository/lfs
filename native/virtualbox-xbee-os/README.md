# Tester XBee OS dans VirtualBox

```bash
cd native/virtualbox-xbee-os
xbee validate
xbee pack
xbee up
xbee enter
```

La VM `xbee-os1` dispose de 2 CPU et 2 Gio de mémoire. Pour exécuter le test
complet et supprimer automatiquement la VM :

```bash
./smoke.sh
```

Pour supprimer manuellement l'environnement :

```bash
xbee delete --force
```
