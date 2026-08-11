#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 9 ]]; then
  echo "usage: build-package-release-system.sh BIOS BIOS_META UEFI UEFI_META NAME SIGNING_KEY RESOURCES SRC OUT" >&2
  exit 2
fi

bios_image=$1
bios_metadata=$2
uefi_image=$3
uefi_metadata=$4
release_name=$5
signing_key=$6
resources=$7
source_root=$8
output_root=$9

[[ "$release_name" =~ ^[A-Za-z0-9._-]+$ ]] || {
  echo "invalid release name: $release_name" >&2
  exit 2
}
[[ -f "$signing_key" && ! -L "$signing_key" ]] ||
  { echo "release signing key not found" >&2; exit 1; }
openssl pkey -in "$signing_key" -noout >/dev/null 2>&1 ||
  { echo "invalid release signing key" >&2; exit 1; }

verify_artefact() {
  local artefact=$1
  [[ -f "$artefact" && -f "$artefact.sha256" ]] || {
    echo "artefact or checksum not found: $artefact" >&2
    exit 1
  }
  (
    cd "$(dirname "$artefact")"
    sha256sum -c "$(basename "$artefact").sha256" >/dev/null
  )
}

verify_artefact "$bios_image"
verify_artefact "$uefi_image"
[[ -s "$bios_metadata" && -s "$uefi_metadata" ]] || {
  echo "release metadata input is missing" >&2
  exit 1
}
grep -Fq 'firmware: bios' "$bios_metadata"
grep -Fq 'package-count: 446' "$bios_metadata"
grep -Fq 'firmware: uefi' "$uefi_metadata"
grep -Fq 'package-count: 446' "$uefi_metadata"
for resource in README.release.md meta-data user-data verify-release.sh; do
  [[ -f "$resources/$resource" ]] || {
    echo "release resource not found: $resource" >&2
    exit 1
  }
done

work_root="$source_root/package-release-system"
release_dir="$work_root/$release_name"
output_dir="$output_root/opt/xbee-lfs-native"
archive="$output_dir/$release_name-release.tar.zst"

rm -rf "$work_root"
mkdir -p \
  "$release_dir/images" \
  "$release_dir/metadata" \
  "$release_dir/nocloud-seed" \
  "$output_dir"
install -m 0644 "$bios_image" "$release_dir/images/"
install -m 0644 "$uefi_image" "$release_dir/images/"
install -m 0644 "$bios_metadata" "$release_dir/metadata/"
install -m 0644 "$uefi_metadata" "$release_dir/metadata/"
install -m 0644 "$resources/README.release.md" "$release_dir/README.md"
install -m 0644 "$resources/meta-data" "$release_dir/nocloud-seed/meta-data"
install -m 0644 "$resources/user-data" "$release_dir/nocloud-seed/user-data"

cat >"$release_dir/release.yaml" <<EOF
schema-version: 1
name: "$release_name"
lfs-book: "13.0"
repository-version: "0.34.1"
architecture: x86_64
kernel: "6.18.10"
package-count: 446
images:
  bios:
    file: "images/$(basename "$bios_image")"
    firmware: bios
    partition-table: msdos
  uefi:
    file: "images/$(basename "$uefi_image")"
    firmware: uefi
    partition-table: gpt
nocloud:
  implementation: xbee-nocloud
  seed-template: nocloud-seed
checksums: SHA256SUMS
EOF

(
  cd "$release_dir"
  find README.md images metadata nocloud-seed release.yaml \
    -type f -print0 |
    sort -z |
    xargs -0 sha256sum >SHA256SUMS
  sha256sum -c SHA256SUMS >/dev/null
)

tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner \
  --zstd -C "$work_root" -cf "$archive" "$release_name"
(
  cd "$output_dir"
  sha256sum "$(basename "$archive")" >"$(basename "$archive").sha256"
)

cat >"$output_dir/package-release-metadata.yaml" <<EOF
schema-version: 1
stage: package-release-system
name: "$release_name"
format: tar.zst
archive: "$(basename "$archive")"
archive-checksum: "$(basename "$archive").sha256"
package-count: 446
artifact-signature: ed25519
artifact-key-id: ARTIFACTS.keyid
artifact-manifest: ARTIFACTS
artifact-verifier: verify-release.sh
contains:
  - bios-qcow2
  - uefi-qcow2
  - package-metadata
  - nocloud-seed-template
  - sha256-manifest
  - signed-artifact-manifest
EOF

install -m 0755 "$resources/verify-release.sh" \
  "$output_dir/verify-release.sh"
openssl pkey -in "$signing_key" -pubout \
  -out "$output_dir/release-ed25519-public.pem"
openssl pkey -pubin -in "$output_dir/release-ed25519-public.pem" \
  -outform DER |
  sha256sum | awk '{print $1}' >"$output_dir/ARTIFACTS.keyid"
cat >"$output_dir/ARTIFACTS.release" <<'EOF'
schema-version: 1
published-at: "2026-08-01T00:00:00Z"
expires-at: "2027-08-01T00:00:00Z"
EOF
(
  cd "$output_dir"
  for filename in \
    "$(basename "$archive")" \
    "$(basename "$archive").sha256" \
    package-release-metadata.yaml \
    ARTIFACTS.release \
    verify-release.sh; do
    printf '%s %s %s\n' \
      "$(sha256sum "$filename" | awk '{print $1}')" \
      "$(stat -c %s "$filename")" \
      "$filename"
  done >ARTIFACTS
)
openssl pkeyutl -sign -inkey "$signing_key" -rawin \
  -in "$output_dir/ARTIFACTS" -out "$output_dir/ARTIFACTS.sig"
"$output_dir/verify-release.sh" "$output_dir" \
  "$output_dir/release-ed25519-public.pem" >/dev/null

verification_fixture="$source_root/release-verification-fixture"
rm -rf "$verification_fixture"
mkdir -p "$verification_fixture"
cp -al "$output_dir/." "$verification_fixture/"
rm "$verification_fixture/$(basename "$archive")"
printf 'tampered\n' >"$verification_fixture/$(basename "$archive")"
if "$output_dir/verify-release.sh" "$verification_fixture" \
  "$output_dir/release-ed25519-public.pem" >/dev/null 2>&1; then
  echo "tampered release verification unexpectedly succeeded" >&2
  exit 1
fi
rm -rf "$verification_fixture"
mkdir -p "$verification_fixture"
cp -al "$output_dir/." "$verification_fixture/"
rm "$verification_fixture/package-release-metadata.yaml"
if "$output_dir/verify-release.sh" "$verification_fixture" \
  "$output_dir/release-ed25519-public.pem" >/dev/null 2>&1; then
  echo "missing release artefact verification unexpectedly succeeded" >&2
  exit 1
fi
rm -rf "$verification_fixture"
mkdir -p "$verification_fixture"
cp -al "$output_dir/." "$verification_fixture/"
touch "$verification_fixture/unexpected"
if "$output_dir/verify-release.sh" "$verification_fixture" \
  "$output_dir/release-ed25519-public.pem" >/dev/null 2>&1; then
  echo "unexpected release artefact verification unexpectedly succeeded" >&2
  exit 1
fi
rm -rf "$verification_fixture"
