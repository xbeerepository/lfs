#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: build-package.sh FINAL_ROOTFS SRC OUT" >&2
  exit 2
fi

rootfs_archive=$1
source_root=$2
output_root=$3
version=15.2.0
work_root="$source_root/package-libstdcxx-runtime"
system_root="$work_root/system"
metadata="$work_root/metadata"
payload="$metadata/rootfs"
output_dir="$output_root/opt/xbee-lfs-packages"

[[ -f "$rootfs_archive" && -f "$rootfs_archive.sha256" ]] || {
  echo "verified final rootfs not found: $rootfs_archive" >&2
  exit 1
}
expected=$(awk 'NR == 1 {print $1}' "$rootfs_archive.sha256")
actual=$(sha256sum "$rootfs_archive" | awk '{print $1}')
[[ -n "$expected" && "$expected" == "$actual" ]] || {
  echo "final rootfs checksum mismatch" >&2
  exit 1
}

rm -rf "$work_root"
runtime_dir="$payload/usr/lib/xbee-runtime"
mkdir -p "$system_root" "$runtime_dir" "$metadata/.XBPKG" "$output_dir"
tar --zstd --numeric-owner -xf "$rootfs_archive" -C "$system_root"

for library in libgcc_s.so.1 libstdc++.so.6.0.34; do
  source="$system_root/usr/lib/$library"
  [[ -f "$source" && ! -L "$source" ]] || {
    echo "GCC runtime library not found: $library" >&2
    exit 1
  }
  install -m 0755 "$source" "$runtime_dir/$library"
done
ln -s libstdc++.so.6.0.34 "$runtime_dir/libstdc++.so.6"
install -Dm0644 /dev/stdin \
  "$payload/etc/ld.so.conf.d/xbee-libstdcxx-runtime.conf" <<'EOF'
/usr/lib/xbee-runtime
EOF

(
  cd "$payload"
  find . \( -type f -o -type l \) -printf '/%P\n' |
    LC_ALL=C sort >../.XBPKG/files
  find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum \
    >../.XBPKG/files.sha256
)
: >"$metadata/.XBPKG/conffiles"
cat >"$metadata/.XBPKG/manifest.yaml" <<EOF
schema-version: 1
name: "libstdcxx-runtime"
version: "$version"
architecture: x86_64
dependencies: "glibc"
payload: rootfs
files: .XBPKG/files
checksums: .XBPKG/files.sha256
conffiles: .XBPKG/conffiles
EOF

archive="$output_dir/libstdcxx-runtime-$version-x86_64.xbpkg.tar.zst"
tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner \
  --zstd -C "$metadata" -cf "$archive" .XBPKG rootfs
(cd "$output_dir" && sha256sum "$(basename "$archive")" \
  >"$(basename "$archive").sha256")
