#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 5 ]]; then
  echo "usage: build-package-repository.sh XBPKG PACKAGES SIGNING_KEY SRC OUT" >&2
  exit 2
fi

manager=$1
packages_root=$2
signing_key=$3
source_root=$4
output_root=$5
repository="$output_root/opt/xbee-lfs-repository"
test_root="$source_root/xbpkg-test-root"
collision_root="$source_root/xbpkg-collision-root"
upgrade_root="$source_root/xbpkg-upgrade-root"
resolution_root="$source_root/xbpkg-resolution-root"
resolution_plan="$source_root/xbpkg-resolution-plan.txt"
lock_root="$source_root/xbpkg-lock-root"
lock_ready="$source_root/xbpkg-lock-ready"
lock_release="$source_root/xbpkg-lock-release"
prune_root="$source_root/xbpkg-prune-root"
recovery_root="$source_root/xbpkg-recovery-root"
signature_root="$source_root/xbpkg-signature-root"

[[ -x "$manager" && -f "$manager.sha256" ]] || {
  echo "xbpkg artefact not found" >&2
  exit 1
}
[[ -f "$signing_key" && ! -L "$signing_key" ]] || {
  echo "repository signing key not found" >&2
  exit 1
}
openssl pkey -in "$signing_key" -noout >/dev/null 2>&1 || {
  echo "invalid repository signing key" >&2
  exit 1
}
expected=$(awk 'NR == 1 {print $1}' "$manager.sha256")
actual=$(sha256sum "$manager" | awk '{print $1}')
[[ -n "$expected" && "$expected" == "$actual" ]] || {
  echo "xbpkg checksum mismatch" >&2
  exit 1
}

rm -rf \
  "$repository" "$test_root" "$collision_root" "$upgrade_root" \
  "$resolution_root" "$resolution_plan" "$lock_root" \
  "$lock_ready" "$lock_release" "$prune_root" "$recovery_root" \
  "$signature_root"
mkdir -p \
  "$repository/packages" "$repository/bin" "$test_root" \
  "$collision_root/usr/lib" "$upgrade_root" "$resolution_root" \
  "$lock_root/var/lib/xbpkg" "$prune_root"
mkdir -p "$recovery_root"
install -m 0755 "$manager" "$repository/bin/xbpkg"
"$repository/bin/xbpkg" --root "$test_root" list >/dev/null

package_count=0
for package in "$packages_root"/*.xbpkg.tar.zst; do
  [[ -f "$package" && -f "$package.sha256" ]] || continue
  expected=$(awk 'NR == 1 {print $1}' "$package.sha256")
  actual=$(sha256sum "$package" | awk '{print $1}')
  [[ -n "$expected" && "$expected" == "$actual" ]] || {
    echo "package checksum mismatch: $package" >&2
    exit 1
  }
  install -m 0644 "$package" "$repository/packages/"
  package_count=$((package_count + 1))
done
[[ "$package_count" -eq 91 ]] || {
  echo "expected 91 packages, found $package_count" >&2
  exit 1
}

cat >"$repository/index.yaml" <<'EOF'
schema-version: 1
repository: xbee-lfs-native
version: "0.34.1"
architecture: x86_64
format: xbpkg.tar.zst
packages:
  - name: glibc
    version: "2.43"
    essential: true
  - name: zlib
    version: "1.3.2"
  - name: bzip2
    version: "1.0.8"
  - name: xz
    version: "5.8.2"
  - name: zstd
    version: "1.5.7"
  - name: lz4
    version: "1.10.0"
  - name: attr
    version: "2.5.2"
  - name: acl
    version: "2.3.2"
    dependencies:
      - attr
  - name: libpipeline
    version: "1.5.8"
  - name: man-db
    version: "2.13.1"
    dependencies:
      - libpipeline
      - zlib
  - name: ncurses
    version: "6.6"
  - name: readline
    version: "8.3"
    dependencies:
      - ncurses
  - name: pcre2
    version: "10.47"
    dependencies:
      - zlib
      - bzip2
      - readline
  - name: libcap
    version: "2.77"
  - name: libelf
    version: "0.194"
    dependencies:
      - zlib
      - zstd
      - xz
      - bzip2
  - name: gmp
    version: "6.3.0"
  - name: mpfr
    version: "4.2.2"
    dependencies:
      - gmp
  - name: mpc
    version: "1.3.1"
    dependencies:
      - gmp
      - mpfr
  - name: m4
    version: "1.4.21"
  - name: bison
    version: "3.8.2"
    dependencies:
      - m4
  - name: flex
    version: "2.6.4"
    dependencies:
      - m4
  - name: autoconf
    version: "2.72"
    dependencies:
      - m4
  - name: automake
    version: "1.18.1"
    dependencies:
      - autoconf
  - name: libtool
    version: "2.5.4"
    dependencies:
      - m4
  - name: pkgconf
    version: "2.5.1"
  - name: binutils
    version: "2.46.0"
    dependencies:
      - zlib
      - zstd
      - flex
  - name: gcc
    version: "15.2.0"
    dependencies:
      - binutils
      - zlib
      - zstd
      - gmp
      - mpfr
      - mpc
  - name: libffi
    version: "3.5.2"
  - name: expat
    version: "2.7.4"
  - name: gdbm
    version: "1.26"
    dependencies:
      - readline
  - name: openssl
    version: "3.6.1"
    dependencies:
      - zlib
  - name: sqlite
    version: "3.51.2"
    dependencies:
      - zlib
      - readline
  - name: python
    version: "3.14.3"
    dependencies:
      - bzip2
      - xz
      - zlib
      - zstd
      - ncurses
      - readline
      - libffi
      - expat
      - gdbm
      - openssl
      - sqlite
  - name: flit-core
    version: "3.12.0"
    dependencies:
      - python
  - name: packaging
    version: "26.0"
    dependencies:
      - python
      - flit-core
  - name: markupsafe
    version: "3.0.3"
    dependencies:
      - python
  - name: jinja2
    version: "3.1.6"
    dependencies:
      - python
      - markupsafe
  - name: meson
    version: "1.10.1"
    dependencies:
      - python
      - packaging
  - name: ninja
    version: "1.13.2"
    dependencies:
      - python
  - name: bc
    version: "7.0.3"
    dependencies:
      - readline
  - name: gperf
    version: "3.3"
    dependencies:
      - gcc
  - name: libxcrypt
    version: "4.5.2"
  - name: less
    version: "692"
    dependencies:
      - ncurses
  - name: kmod
    version: "34.2"
    dependencies:
      - zlib
      - zstd
      - xz
      - openssl
  - name: procps-ng
    version: "4.0.6"
    dependencies:
      - ncurses
  - name: e2fsprogs
    version: "1.47.3"
  - name: shadow
    version: "4.19.3"
    dependencies:
      - libxcrypt
      - attr
      - acl
  - name: iproute2
    version: "6.18.0"
    dependencies:
      - libcap
      - libelf
  - name: inetutils
    version: "2.7"
    dependencies:
      - ncurses
      - readline
      - libxcrypt
  - name: kbd
    version: "2.9.0"
  - name: psmisc
    version: "23.7"
    dependencies:
      - ncurses
  - name: man-pages
    version: "6.17"
  - name: iana-etc
    version: "20260202"
  - name: file
    version: "5.46"
    dependencies:
      - zlib
      - bzip2
      - xz
      - zstd
  - name: tcl
    version: "8.6.17"
    dependencies:
      - zlib
  - name: expect
    version: "5.45.4"
    dependencies:
      - tcl
  - name: dejagnu
    version: "1.6.3"
    dependencies:
      - expect
  - name: sed
    version: "4.9"
    dependencies:
      - acl
  - name: gettext
    version: "1.0"
    dependencies:
      - acl
      - attr
      - gcc
      - ncurses
  - name: grep
    version: "3.12"
    dependencies:
      - pcre2
  - name: bash
    version: "5.3"
    dependencies:
      - readline
      - ncurses
  - name: perl
    version: "5.42.0"
    dependencies:
      - zlib
      - bzip2
      - gdbm
      - less
      - libxcrypt
  - name: xml-parser
    version: "2.47"
    dependencies:
      - perl
      - expat
  - name: intltool
    version: "0.51.0"
    dependencies:
      - perl
      - xml-parser
  - name: wheel
    version: "0.46.3"
    dependencies:
      - python
      - flit-core
  - name: setuptools
    version: "82.0.0"
    dependencies:
      - python
  - name: coreutils
    version: "9.10"
    dependencies:
      - acl
      - attr
      - libcap
      - openssl
      - gmp
  - name: diffutils
    version: "3.12"
  - name: gawk
    version: "5.3.2"
    dependencies:
      - gmp
      - mpfr
      - readline
  - name: findutils
    version: "4.10.0"
  - name: groff
    version: "1.23.0"
    dependencies:
      - gcc
      - perl
  - name: gzip
    version: "1.14"
  - name: make
    version: "4.4.1"
  - name: patch
    version: "2.8"
    dependencies:
      - attr
  - name: tar
    version: "1.35"
    dependencies:
      - acl
      - attr
      - bzip2
      - gzip
      - xz
      - zstd
  - name: texinfo
    version: "7.2"
    dependencies:
      - perl
      - ncurses
  - name: vim
    version: "9.2.0078"
    dependencies:
      - ncurses
      - acl
  - name: dbus
    version: "1.16.2"
    dependencies:
      - expat
  - name: util-linux
    version: "2.41.3"
    dependencies:
      - ncurses
      - readline
      - zlib
      - libcap
      - file
      - libxcrypt
  - name: systemd
    version: "259.1"
    dependencies:
      - util-linux
      - kmod
      - libcap
      - openssl
      - acl
      - pcre2
      - zstd
      - xz
      - lz4
      - libxcrypt
      - libelf
      - zlib
      - bzip2
      - dbus
  - name: grub
    version: "2.14"
    dependencies:
      - xz
  - name: linux-headers
    version: "6.18.10"
    dependencies:
      - glibc
  - name: linux-kernel
    version: "6.18.10"
    dependencies:
      - linux-headers
  - name: linux-modules
    version: "6.18.10"
    dependencies:
      - linux-kernel
      - kmod
  - name: openssh
    version: "10.4p1"
    dependencies:
      - openssl
      - zlib
      - libxcrypt
      - systemd
  - name: sudo
    version: "1.9.17p2"
    dependencies:
      - libxcrypt
      - zlib
      - openssl
  - name: ca-certificates
    version: "2026.07.16"
    dependencies:
      - openssl
  - name: wget
    version: "1.25.0"
    dependencies:
      - openssl
      - zlib
      - pcre2
      - util-linux
      - ca-certificates
  - name: curl
    version: "8.21.0"
    dependencies:
      - openssl
      - zlib
      - ca-certificates
  - name: dhcpcd
    version: "10.2.4"
    dependencies:
      - systemd
      - openssl
  - name: rsync
    version: "3.4.4"
    dependencies:
      - zlib
      - zstd
      - lz4
      - openssl
      - acl
      - attr
EOF

cat >"$repository/RELEASE" <<'EOF'
schema-version: 1
repository: xbee-lfs-native
serial: 34
version: "0.34.1"
published-at: "2026-08-01T00:00:00Z"
expires-at: "2027-02-01T00:00:00Z"
EOF
(
  cd "$repository"
  sha256sum RELEASE index.yaml bin/xbpkg packages/*.xbpkg.tar.zst \
    >SHA256SUMS
)
openssl pkey -in "$signing_key" -pubout \
  -out "$repository/repository-ed25519-public.pem"
openssl pkey -pubin -in "$repository/repository-ed25519-public.pem" \
  -outform DER |
  sha256sum | awk '{print $1}' >"$repository/SHA256SUMS.keyid"
openssl pkeyutl -sign -inkey "$signing_key" -rawin \
  -in "$repository/SHA256SUMS" -out "$repository/SHA256SUMS.sig"
export XBPKG_TRUSTED_KEY="$repository/repository-ed25519-public.pem"

mkdir -p "$signature_root/unsigned"
cp -al "$repository/." "$signature_root/unsigned/"
rm "$signature_root/unsigned/SHA256SUMS.sig"
if "$repository/bin/xbpkg" \
  --root "$signature_root/root" \
  --repository "$signature_root/unsigned" \
  --dry-run install curl >/dev/null 2>&1; then
  echo "xbpkg unsigned repository test unexpectedly succeeded" >&2
  exit 1
fi
"$repository/bin/xbpkg" \
  --root "$signature_root/root" \
  --repository "$signature_root/unsigned" \
  --allow-unsigned --dry-run install curl >/dev/null
cp "$repository/SHA256SUMS.sig" "$signature_root/unsigned/SHA256SUMS.sig"
printf 'tampered\n' >>"$signature_root/unsigned/SHA256SUMS.sig"
if "$repository/bin/xbpkg" \
  --root "$signature_root/root" \
  --repository "$signature_root/unsigned" \
  --allow-unsigned --dry-run install curl >/dev/null 2>&1; then
  echo "xbpkg invalid repository signature test unexpectedly succeeded" >&2
  exit 1
fi
openssl genpkey -algorithm Ed25519 \
  -out "$signature_root/unknown-private.pem"
openssl pkey -in "$signature_root/unknown-private.pem" -pubout \
  -out "$signature_root/unknown-public.pem"
if XBPKG_TRUSTED_KEY="$signature_root/unknown-public.pem" \
  "$repository/bin/xbpkg" \
    --root "$signature_root/root" \
    --repository "$repository" \
    --dry-run install curl >/dev/null 2>&1; then
  echo "xbpkg unknown repository key test unexpectedly succeeded" >&2
  exit 1
fi
mkdir -p "$signature_root/keyring"
cp "$repository/repository-ed25519-public.pem" \
  "$signature_root/keyring/original.pem"
cp "$signature_root/unknown-public.pem" \
  "$signature_root/keyring/rotated.pem"
mkdir -p "$signature_root/rotated"
cp -al "$repository/." "$signature_root/rotated/"
rm "$signature_root/rotated/SHA256SUMS.sig" \
  "$signature_root/rotated/SHA256SUMS.keyid"
openssl pkeyutl -sign -inkey "$signature_root/unknown-private.pem" -rawin \
  -in "$signature_root/rotated/SHA256SUMS" \
  -out "$signature_root/rotated/SHA256SUMS.sig"
openssl pkey -pubin -in "$signature_root/unknown-public.pem" -outform DER |
  sha256sum | awk '{print $1}' \
    >"$signature_root/rotated/SHA256SUMS.keyid"
XBPKG_TRUSTED_KEY= \
XBPKG_TRUSTED_KEYRING="$signature_root/keyring" \
  "$repository/bin/xbpkg" \
    --root "$signature_root/root" \
    --repository "$signature_root/rotated" \
    --dry-run install curl >/dev/null
cp "$repository/SHA256SUMS.keyid" "$signature_root/revoked-keys"
if XBPKG_TRUSTED_KEY= \
  XBPKG_TRUSTED_KEYRING="$signature_root/keyring" \
  XBPKG_REVOKED_KEYS="$signature_root/revoked-keys" \
  "$repository/bin/xbpkg" \
    --root "$signature_root/root" \
    --repository "$repository" \
    --dry-run install curl >/dev/null 2>&1; then
  echo "xbpkg revoked repository key test unexpectedly succeeded" >&2
  exit 1
fi
XBPKG_TRUSTED_KEY= \
XBPKG_TRUSTED_KEYRING="$signature_root/keyring" \
XBPKG_REVOKED_KEYS="$signature_root/revoked-keys" \
  "$repository/bin/xbpkg" \
    --root "$signature_root/root" \
    --repository "$signature_root/rotated" \
    --dry-run install curl >/dev/null

"$repository/bin/xbpkg" \
  --root "$resolution_root" \
  --repository "$repository" \
  --dry-run \
  install curl >"$resolution_plan"
[[ "$(grep -c '^  install ' "$resolution_plan")" -eq 4 ]]
[[ ! -e "$resolution_root/var/lib/xbpkg" &&
   ! -e "$resolution_root/usr" &&
   ! -e "$resolution_root/etc" ]]

"$repository/bin/xbpkg" \
  --root "$resolution_root" \
  --repository "$repository" \
  install curl
[[ "$("$repository/bin/xbpkg" --root "$resolution_root" list | wc -l)" -eq 4 ]]
"$repository/bin/xbpkg" --root "$resolution_root" verify curl

mkdir -p "$signature_root/downgraded"
cp -al "$repository/." "$signature_root/downgraded/"
rm "$signature_root/downgraded/RELEASE" \
  "$signature_root/downgraded/SHA256SUMS" \
  "$signature_root/downgraded/SHA256SUMS.sig"
sed -e 's/^serial: 34$/serial: 33/' \
  -e 's/version: "0.34.1"/version: "0.33.0"/' \
  "$repository/RELEASE" >"$signature_root/downgraded/RELEASE"
(
  cd "$signature_root/downgraded"
  sha256sum RELEASE index.yaml bin/xbpkg packages/*.xbpkg.tar.zst \
    >SHA256SUMS
)
openssl pkeyutl -sign -inkey "$signing_key" -rawin \
  -in "$signature_root/downgraded/SHA256SUMS" \
  -out "$signature_root/downgraded/SHA256SUMS.sig"
if "$repository/bin/xbpkg" \
  --root "$resolution_root" \
  --repository "$signature_root/downgraded" \
  --dry-run install curl >/dev/null 2>&1; then
  echo "xbpkg repository downgrade test unexpectedly succeeded" >&2
  exit 1
fi
"$repository/bin/xbpkg" \
  --root "$resolution_root" \
  --repository "$signature_root/downgraded" \
  --allow-downgrade --dry-run install curl >/dev/null
sed -e 's/^serial: 33$/serial: 34/' \
  -e 's/version: "0.33.0"/version: "0.34.1-reused"/' \
  "$signature_root/downgraded/RELEASE" \
  >"$signature_root/reused-release"
mv "$signature_root/reused-release" "$signature_root/downgraded/RELEASE"
(
  cd "$signature_root/downgraded"
  sha256sum RELEASE index.yaml bin/xbpkg packages/*.xbpkg.tar.zst \
    >SHA256SUMS
)
openssl pkeyutl -sign -inkey "$signing_key" -rawin \
  -in "$signature_root/downgraded/SHA256SUMS" \
  -out "$signature_root/downgraded/SHA256SUMS.sig"
if "$repository/bin/xbpkg" \
  --root "$resolution_root" \
  --repository "$signature_root/downgraded" \
  --allow-downgrade --dry-run install curl >/dev/null 2>&1; then
  echo "xbpkg reused repository serial test unexpectedly succeeded" >&2
  exit 1
fi

if "$repository/bin/xbpkg" --root "$test_root" install \
  "$repository/packages/acl-2.3.2-x86_64.xbpkg.tar.zst" >/dev/null 2>&1; then
  echo "xbpkg missing dependency test unexpectedly succeeded" >&2
  exit 1
fi
for name in \
  glibc zlib bzip2 xz zstd lz4 attr acl libpipeline man-db \
  ncurses readline pcre2 libcap libelf gmp mpfr mpc m4 bison flex \
  autoconf automake libtool pkgconf binutils gcc \
  libffi expat gdbm openssl sqlite python \
  flit-core packaging markupsafe jinja2 meson ninja \
  bc gperf libxcrypt less kmod procps-ng \
  e2fsprogs shadow iproute2 inetutils kbd psmisc \
  man-pages iana-etc file tcl expect dejagnu \
  sed gettext grep bash perl xml-parser \
  intltool wheel setuptools coreutils diffutils gawk \
  findutils groff gzip make patch tar \
  texinfo vim dbus util-linux systemd grub \
  linux-headers linux-kernel linux-modules openssh sudo \
  ca-certificates wget curl dhcpcd rsync; do
  package=$(find "$repository/packages" -maxdepth 1 -type f \
    -name "$name-*.xbpkg.tar.zst" -print -quit)
  [[ -n "$package" ]] || {
    echo "package missing from repository: $name" >&2
    exit 1
  }
  "$repository/bin/xbpkg" --root "$test_root" install "$package"
done
installed=$("$repository/bin/xbpkg" --root "$test_root" list | wc -l)
[[ "$installed" -eq 91 ]] || {
  echo "repository installation test did not register all packages" >&2
  exit 1
}
for name in \
  glibc zlib bzip2 xz zstd lz4 attr acl libpipeline man-db \
  ncurses readline pcre2 libcap libelf gmp mpfr mpc m4 bison flex \
  autoconf automake libtool pkgconf binutils gcc \
  libffi expat gdbm openssl sqlite python \
  flit-core packaging markupsafe jinja2 meson ninja \
  bc gperf libxcrypt less kmod procps-ng \
  e2fsprogs shadow iproute2 inetutils kbd psmisc \
  man-pages iana-etc file tcl expect dejagnu \
  sed gettext grep bash perl xml-parser \
  intltool wheel setuptools coreutils diffutils gawk \
  findutils groff gzip make patch tar \
  texinfo vim dbus util-linux systemd grub \
  linux-headers linux-kernel linux-modules openssh sudo \
  ca-certificates wget curl dhcpcd rsync; do
  "$repository/bin/xbpkg" --root "$test_root" verify "$name"
done
"$repository/bin/xbpkg" --root "$test_root" check
[[ "$("$repository/bin/xbpkg" --root "$test_root" owner /usr/bin/xz)" == xz ]]
"$repository/bin/xbpkg" \
  --root "$test_root" \
  --repository "$repository" \
  --dry-run update | grep -q '^  nothing to do$'
"$repository/bin/xbpkg" \
  --root "$test_root" \
  --repository "$repository" \
  update | grep -q '^  nothing to do$'

tar --zstd -xf \
  "$repository/packages/zlib-1.3.2-x86_64.xbpkg.tar.zst" \
  -C "$upgrade_root"
sed -i 's/version: "1.3.2"/version: "1.3.2-test"/' \
  "$upgrade_root/.XBPKG/manifest.yaml"
tar --zstd -C "$upgrade_root" \
  -cf "$source_root/zlib-1.3.2-test-x86_64.xbpkg.tar.zst" \
  .XBPKG rootfs
"$repository/bin/xbpkg" --root "$test_root" upgrade \
  "$source_root/zlib-1.3.2-test-x86_64.xbpkg.tar.zst"
"$repository/bin/xbpkg" --root "$test_root" verify zlib
[[ "$("$repository/bin/xbpkg" --root "$test_root" list |
  awk '$1 == "zlib" {print $2}')" == 1.3.2-test ]]

"$repository/bin/xbpkg" --root "$test_root" remove diffutils
[[ ! -e "$test_root/usr/bin/diff3" ]]
if "$repository/bin/xbpkg" --root "$test_root" remove attr >/dev/null 2>&1; then
  echo "xbpkg reverse dependency test unexpectedly succeeded" >&2
  exit 1
fi
if "$repository/bin/xbpkg" --root "$test_root" remove acl >/dev/null 2>&1; then
  echo "xbpkg shadow dependency test unexpectedly succeeded" >&2
  exit 1
fi
"$repository/bin/xbpkg" --root "$test_root" remove shadow
if "$repository/bin/xbpkg" --root "$test_root" remove acl >/dev/null 2>&1; then
  echo "xbpkg sed/gettext dependency test unexpectedly succeeded" >&2
  exit 1
fi
if "$repository/bin/xbpkg" --root "$test_root" remove \
  libpipeline >/dev/null 2>&1; then
  echo "xbpkg libpipeline dependency test unexpectedly succeeded" >&2
  exit 1
fi
if "$repository/bin/xbpkg" --root "$test_root" remove \
  binutils >/dev/null 2>&1; then
  echo "xbpkg binutils dependency test unexpectedly succeeded" >&2
  exit 1
fi
if "$repository/bin/xbpkg" --root "$test_root" remove \
  sqlite >/dev/null 2>&1; then
  echo "xbpkg sqlite dependency test unexpectedly succeeded" >&2
  exit 1
fi
if "$repository/bin/xbpkg" --root "$test_root" remove \
  markupsafe >/dev/null 2>&1; then
  echo "xbpkg markupsafe dependency test unexpectedly succeeded" >&2
  exit 1
fi
if "$repository/bin/xbpkg" --root "$test_root" remove \
  packaging >/dev/null 2>&1; then
  echo "xbpkg packaging dependency test unexpectedly succeeded" >&2
  exit 1
fi
if "$repository/bin/xbpkg" --root "$test_root" remove \
  gcc >/dev/null 2>&1; then
  echo "xbpkg gcc dependency test unexpectedly succeeded" >&2
  exit 1
fi
if "$repository/bin/xbpkg" --root "$test_root" remove \
  libxcrypt >/dev/null 2>&1; then
  echo "xbpkg libxcrypt dependency test unexpectedly succeeded" >&2
  exit 1
fi
if "$repository/bin/xbpkg" --root "$test_root" remove \
  tcl >/dev/null 2>&1; then
  echo "xbpkg tcl dependency test unexpectedly succeeded" >&2
  exit 1
fi
if "$repository/bin/xbpkg" --root "$test_root" remove \
  expect >/dev/null 2>&1; then
  echo "xbpkg expect dependency test unexpectedly succeeded" >&2
  exit 1
fi
if "$repository/bin/xbpkg" --root "$test_root" remove \
  xml-parser >/dev/null 2>&1; then
  echo "xbpkg xml-parser dependency test unexpectedly succeeded" >&2
  exit 1
fi
if "$repository/bin/xbpkg" --root "$test_root" remove \
  gzip >/dev/null 2>&1; then
  echo "xbpkg gzip dependency test unexpectedly succeeded" >&2
  exit 1
fi
if "$repository/bin/xbpkg" --root "$test_root" remove \
  util-linux >/dev/null 2>&1; then
  echo "xbpkg util-linux dependency test unexpectedly succeeded" >&2
  exit 1
fi
if "$repository/bin/xbpkg" --root "$test_root" remove \
  dbus >/dev/null 2>&1; then
  echo "xbpkg dbus dependency test unexpectedly succeeded" >&2
  exit 1
fi
if "$repository/bin/xbpkg" --root "$test_root" remove \
  linux-kernel >/dev/null 2>&1; then
  echo "xbpkg linux-kernel dependency test unexpectedly succeeded" >&2
  exit 1
fi
if "$repository/bin/xbpkg" --root "$test_root" remove \
  ca-certificates >/dev/null 2>&1; then
  echo "xbpkg ca-certificates dependency test unexpectedly succeeded" >&2
  exit 1
fi
if "$repository/bin/xbpkg" --root "$test_root" remove \
  glibc >/dev/null 2>&1; then
  echo "xbpkg essential package test unexpectedly succeeded" >&2
  exit 1
fi

touch "$collision_root/usr/lib/libz.so.1.3.2"
if "$repository/bin/xbpkg" --root "$collision_root" install \
  "$repository/packages/zlib-1.3.2-x86_64.xbpkg.tar.zst" >/dev/null 2>&1; then
  echo "xbpkg collision test unexpectedly succeeded" >&2
  exit 1
fi

(
  flock -x 9
  touch "$lock_ready"
  while [[ ! -e "$lock_release" ]]; do sleep 0.05; done
) 9>"$lock_root/var/lib/xbpkg/lock" &
lock_holder=$!
for _ in {1..100}; do
  [[ -e "$lock_ready" ]] && break
  sleep 0.01
done
[[ -e "$lock_ready" ]] || {
  touch "$lock_release"
  wait "$lock_holder"
  echo "xbpkg lock holder did not start" >&2
  exit 1
}
set +e
lock_output=$("$repository/bin/xbpkg" --root "$lock_root" install \
  "$repository/packages/zlib-1.3.2-x86_64.xbpkg.tar.zst" 2>&1)
lock_status=$?
set -e
touch "$lock_release"
wait "$lock_holder"
[[ "$lock_status" -ne 0 &&
   "$lock_output" == *"another package operation is active"* &&
   ! -e "$lock_root/usr/lib/libz.so.1.3.2" ]] || {
  echo "xbpkg concurrent mutation test unexpectedly succeeded" >&2
  exit 1
}

mkdir -p "$prune_root/usr/share/prune-shared"
printf 'unmanaged\n' >"$prune_root/usr/share/prune-shared/unmanaged"
"$repository/bin/xbpkg" --root "$prune_root" install \
  "$repository/packages/lz4-1.10.0-x86_64.xbpkg.tar.zst"
"$repository/bin/xbpkg" --root "$prune_root" remove lz4
[[ -d "$prune_root/usr" &&
   ! -e "$prune_root/usr/include" &&
   -f "$prune_root/usr/share/prune-shared/unmanaged" ]] || {
  echo "xbpkg empty directory pruning test failed" >&2
  exit 1
}

"$repository/bin/xbpkg" --root "$recovery_root" install \
  "$repository/packages/lz4-1.10.0-x86_64.xbpkg.tar.zst"
recovery_journal="$recovery_root/var/lib/xbpkg/transactions/current"
mkdir -p "$recovery_journal"
cp "$recovery_root/var/lib/xbpkg/installed/lz4/files" \
  "$recovery_journal/files"
printf 'lz4\n' >"$recovery_journal/packages"
printf 'prepared\n' >"$recovery_journal/state"
: >"$recovery_journal/completed"
if "$repository/bin/xbpkg" --root "$recovery_root" check \
  >/dev/null 2>&1; then
  echo "xbpkg abandoned transaction check unexpectedly succeeded" >&2
  exit 1
fi
"$repository/bin/xbpkg" --root "$recovery_root" recover
[[ ! -e "$recovery_journal" &&
   ! -e "$recovery_root/usr/include/lz4.h" &&
   -z "$("$repository/bin/xbpkg" --root "$recovery_root" list)" ]] || {
  echo "xbpkg persistent transaction recovery failed" >&2
  exit 1
}

cat >"$output_root/opt/xbee-lfs-repository-metadata.yaml" <<'EOF'
schema-version: 1
stage: package-repository
manager: xbpkg
manager-version: "0.18.1"
architecture: x86_64
package-count: 91
tests:
  install: true
  upgrade: true
  list: true
  owner: true
  verify: true
  check: true
  remove: true
  collision: true
  dependencies: true
  dependency-resolution: true
  configured-repositories: true
  http-repository-cache: true
  repository-refresh: true
  dry-run: true
  transactional-install: true
  transactional-update: true
  mutation-locking: true
  directory-pruning: true
  persistent-transactions: true
  recovery: true
  repository-signature: ed25519
  unsigned-opt-in: true
  unknown-key-rejection: true
  versioned-dependencies: true
  incompatible-upgrade-rejection: true
  signing-key-identifiers: true
  signing-key-rotation: true
  signing-key-revocation: true
  signed-release-metadata: true
  downgrade-protection: true
  serial-reuse-rejection: true
  expiration: true
  future-publication-rejection: true
EOF
