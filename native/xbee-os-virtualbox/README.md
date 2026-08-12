# XBee OS VirtualBox

Ce système conserve le pack `xbee-os` minimal pour les conteneurs et ajoute
une variante amorçable destinée au provider VirtualBox. Elle contient le
noyau, GRUB, systemd, le réseau, SSH et l'agent NoCloud XBee.

L'image VMDK est construite par `../package-minimal-system` et doit être
publiée dans la release `v0.3.0` sous le nom
`xbee-os-13.0-x86_64-virtualbox.vmdk`.
