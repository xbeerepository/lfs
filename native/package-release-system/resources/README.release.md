# XBee Linux From Scratch 13.0 — package release

This release contains the x86_64 BIOS and UEFI images assembled from 91
immutable `xbpkg` packages. Neither image embeds a password or SSH key.

## Verify the release

Before extracting or writing an image to disk, pin the independently
distributed release public key and run:

```bash
./verify-release.sh . /path/to/trusted-release-ed25519-public.pem
```

This verifies `ARTIFACTS.sig`, the signing-key identifier, every published
file size and SHA-256 digest, and rejects missing or unexpected artifacts.
After extracting the archive, `sha256sum -c SHA256SUMS` verifies its internal
BIOS and UEFI images, metadata, documentation, and NoCloud templates.

## NoCloud provisioning

Replace `YOUR_SSH_PUBLIC_KEY` in `nocloud-seed/user-data`, then create a seed:

```bash
xorriso -as mkisofs -volid cidata -joliet -rock \
  -output seed.iso nocloud-seed/user-data nocloud-seed/meta-data
```

Attach `seed.iso` as a read-only CD-ROM on the first boot. The administrator
is `xbee`; only SSH public-key authentication is enabled.

## Images

- `images/*-packages.qcow2`: legacy BIOS, MBR and ext4.
- `images/*-packages-uefi.qcow2`: x86_64 UEFI, GPT, FAT32 ESP and ext4.
