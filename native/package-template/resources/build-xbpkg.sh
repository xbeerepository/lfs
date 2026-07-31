#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 9 ]]; then
  echo "usage: build-xbpkg.sh SOURCES ROOTFS NAME VERSION SOURCE DEPS JOBS SRC OUT" >&2
  exit 2
fi

sources=$1
rootfs_archive=$2
package_name=$3
package_version=$4
source_name=$5
dependencies=$6
jobs=$7
source_root=$8
output_root=$9

if [[ ! "$package_name" =~ ^[a-z0-9][a-z0-9+._-]*$ ||
      ! "$package_version" =~ ^[A-Za-z0-9][A-Za-z0-9+._~-]*$ ]]; then
  echo "invalid package identity: $package_name $package_version" >&2
  exit 2
fi
case "$jobs" in
  ''|*[!0-9]*|0)
    echo "lfs.jobs must be a positive integer" >&2
    exit 2
    ;;
esac
for artefact in "$rootfs_archive" "$sources/$source_name"; do
  [[ -f "$artefact" ]] || {
    echo "required artefact not found: $artefact" >&2
    exit 1
  }
done
expected=$(awk 'NR == 1 {print $1}' "$rootfs_archive.sha256")
actual=$(sha256sum "$rootfs_archive" | awk '{print $1}')
[[ -n "$expected" && "$expected" == "$actual" ]] || {
  echo "final rootfs checksum mismatch" >&2
  exit 1
}

work_root="$source_root/package-$package_name"
rootfs="$work_root/rootfs"
build_dir="$rootfs/sources/xbpkg-$package_name"
stage="$rootfs/stage"
metadata="$work_root/metadata"
output_dir="$output_root/opt/xbee-lfs-packages"
mounted=()

cleanup() {
  local index
  for ((index=${#mounted[@]}-1; index>=0; index--)); do
    umount -l "${mounted[index]}" 2>/dev/null || true
  done
}
trap cleanup EXIT

rm -rf "$work_root"
mkdir -p "$rootfs" "$metadata" "$output_dir"
tar --zstd --xattrs --acls --numeric-owner -xf "$rootfs_archive" -C "$rootfs"
mkdir -p "$rootfs/sources" "$stage"
tar -xf "$sources/$source_name" -C "$rootfs/sources"
source_directory=$(tar -tf "$sources/$source_name" | sed -n '1{s@/.*@@;p;}')
mv "$rootfs/sources/$source_directory" "$build_dir"

mount --bind /dev "$rootfs/dev"
mounted+=("$rootfs/dev")
mount -t devpts devpts "$rootfs/dev/pts"
mounted+=("$rootfs/dev/pts")
mount -t proc proc "$rootfs/proc"
mounted+=("$rootfs/proc")
mount -t sysfs sysfs "$rootfs/sys"
mounted+=("$rootfs/sys")
mount -t tmpfs tmpfs "$rootfs/run"
mounted+=("$rootfs/run")

case "$package_name" in
  zlib)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-zlib &&
        ./configure --prefix=/usr &&
        make -j$jobs &&
        make DESTDIR=/stage install &&
        rm -f /stage/usr/lib/libz.a"
    ;;
  bzip2)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc 'cd /sources/xbpkg-bzip2 &&
        make -f Makefile-libbz2_so &&
        make clean &&
        make -j'"$jobs"' &&
        mkdir -p /stage/usr/bin /stage/usr/lib /stage/usr/include \
          /stage/usr/share/man/man1 /stage/usr/share/doc/bzip2-1.0.8 &&
        install -m 0755 bzip2 bzip2recover \
          bzgrep bzmore bzdiff /stage/usr/bin/ &&
        install -m 0644 bzlib.h /stage/usr/include/ &&
        install -m 0644 bzip2.1 bzgrep.1 bzmore.1 bzdiff.1 \
          /stage/usr/share/man/man1/ &&
        install -m 0644 manual.html manual.pdf manual.ps bzip2.txt \
          /stage/usr/share/doc/bzip2-1.0.8/ &&
        cp -a libbz2.so.1.0.8 /stage/usr/lib/ &&
        ln -sfn libbz2.so.1.0.8 /stage/usr/lib/libbz2.so &&
        ln -sfn libbz2.so.1.0.8 /stage/usr/lib/libbz2.so.1 &&
        install -m 0755 bzip2-shared /stage/usr/bin/bzip2 &&
        ln -sfn bzip2 /stage/usr/bin/bzcat &&
        ln -sfn bzip2 /stage/usr/bin/bunzip2 &&
        ln -sfn bzgrep /stage/usr/bin/bzegrep &&
        ln -sfn bzgrep /stage/usr/bin/bzfgrep &&
        ln -sfn bzmore /stage/usr/bin/bzless &&
        ln -sfn bzdiff /stage/usr/bin/bzcmp'
    ;;
  xz)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-xz &&
        ./configure --prefix=/usr --disable-static \
          --docdir=/usr/share/doc/xz-$package_version &&
        make -j$jobs &&
        make DESTDIR=/stage install"
    ;;
  zstd)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-zstd &&
        make -j$jobs prefix=/usr &&
        make prefix=/usr DESTDIR=/stage install &&
        rm -f /stage/usr/lib/libzstd.a"
    ;;
  *)
    echo "unsupported prototype package: $package_name" >&2
    exit 2
    ;;
esac

for required in usr; do
  [[ -e "$stage/$required" ]] || {
    echo "package payload is empty: $package_name" >&2
    exit 1
  }
done

mkdir -p "$metadata/.XBPKG" "$metadata/rootfs"
cp -a "$stage/." "$metadata/rootfs/"
(
  cd "$metadata/rootfs"
  find . \( -type f -o -type l \) -printf '/%P\n' | LC_ALL=C sort \
    >../.XBPKG/files
  find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum \
    >../.XBPKG/files.sha256
)
cat >"$metadata/.XBPKG/manifest.yaml" <<EOF
schema-version: 1
name: "$package_name"
version: "$package_version"
architecture: x86_64
dependencies: "$dependencies"
payload: rootfs
files: .XBPKG/files
checksums: .XBPKG/files.sha256
EOF

package_archive="$output_dir/$package_name-$package_version-x86_64.xbpkg.tar.zst"
tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner \
  --zstd -C "$metadata" -cf "$package_archive" .XBPKG rootfs
(
  cd "$output_dir"
  sha256sum "$(basename "$package_archive")" \
    >"$(basename "$package_archive").sha256"
)
