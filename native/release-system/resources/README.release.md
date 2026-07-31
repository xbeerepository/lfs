# XBee Linux From Scratch 13.0

This release contains generic x86_64 BIOS and UEFI QCOW2 cloud images, plus a
BIOS VMDK image for the XBee VirtualBox provider.
Neither image embeds a password or SSH key.

## NoCloud provisioning

Replace `YOUR_SSH_PUBLIC_KEY` in `nocloud-seed/user-data`, then create the
seed ISO:

```bash
xorriso -as mkisofs -volid cidata -joliet -rock \
  -output seed.iso nocloud-seed/user-data nocloud-seed/meta-data
```

Attach `seed.iso` as a CD-ROM on the first boot. The administrator is `xbee`.
Only SSH public-key authentication is enabled.

## Image selection

- `images/*-cloud.qcow2`: legacy BIOS with an MBR partition table.
- `images/*-uefi.qcow2`: x86_64 UEFI with GPT and a FAT32 EFI system partition.
- `images/*-virtualbox.vmdk`: legacy BIOS image for `xbee-virtualbox`.

Verify all files before use:

```bash
sha256sum -c SHA256SUMS
```
