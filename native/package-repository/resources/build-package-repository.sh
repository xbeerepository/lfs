#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "usage: build-package-repository.sh XBPKG PACKAGES SRC OUT" >&2
  exit 2
fi

manager=$1
packages_root=$2
source_root=$3
output_root=$4
repository="$output_root/opt/xbee-lfs-repository"
test_root="$source_root/xbpkg-test-root"
collision_root="$source_root/xbpkg-collision-root"

[[ -x "$manager" && -f "$manager.sha256" ]] || {
  echo "xbpkg artefact not found" >&2
  exit 1
}
expected=$(awk 'NR == 1 {print $1}' "$manager.sha256")
actual=$(sha256sum "$manager" | awk '{print $1}')
[[ -n "$expected" && "$expected" == "$actual" ]] || {
  echo "xbpkg checksum mismatch" >&2
  exit 1
}

rm -rf "$repository" "$test_root" "$collision_root"
mkdir -p "$repository/packages" "$repository/bin" "$test_root" "$collision_root/usr/lib"
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
[[ "$package_count" -eq 4 ]] || {
  echo "expected 4 packages, found $package_count" >&2
  exit 1
}

(
  cd "$repository"
  sha256sum bin/xbpkg packages/*.xbpkg.tar.zst >SHA256SUMS
)
cat >"$repository/index.yaml" <<'EOF'
schema-version: 1
repository: xbee-lfs-native
version: "0.1.0"
architecture: x86_64
format: xbpkg.tar.zst
packages:
  - name: zlib
    version: "1.3.2"
  - name: bzip2
    version: "1.0.8"
  - name: xz
    version: "5.8.2"
  - name: zstd
    version: "1.5.7"
EOF

for package in "$repository"/packages/*.xbpkg.tar.zst; do
  "$repository/bin/xbpkg" --root "$test_root" install "$package"
done
installed=$("$repository/bin/xbpkg" --root "$test_root" list | wc -l)
[[ "$installed" -eq 4 ]] || {
  echo "repository installation test did not register all packages" >&2
  exit 1
}
for name in zlib bzip2 xz zstd; do
  "$repository/bin/xbpkg" --root "$test_root" verify "$name"
done
[[ "$("$repository/bin/xbpkg" --root "$test_root" owner /usr/bin/xz)" == xz ]]
"$repository/bin/xbpkg" --root "$test_root" remove zlib
[[ ! -e "$test_root/usr/lib/libz.so.1.3.2" ]]

touch "$collision_root/usr/lib/libz.so.1.3.2"
if "$repository/bin/xbpkg" --root "$collision_root" install \
  "$repository/packages/zlib-1.3.2-x86_64.xbpkg.tar.zst" >/dev/null 2>&1; then
  echo "xbpkg collision test unexpectedly succeeded" >&2
  exit 1
fi

cat >"$output_root/opt/xbee-lfs-repository-metadata.yaml" <<'EOF'
schema-version: 1
stage: package-repository
manager: xbpkg
manager-version: "0.1.0"
architecture: x86_64
package-count: 4
tests:
  install: true
  list: true
  owner: true
  verify: true
  remove: true
  collision: true
EOF
