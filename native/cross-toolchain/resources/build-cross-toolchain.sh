#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "usage: build-cross-toolchain.sh SOURCES JOBS SRC OUT" >&2
  exit 2
fi

source_dir=$1
jobs=$2
source_root=$3
output_root=$4

case "$jobs" in
  ''|*[!0-9]*|0)
    echo "lfs.jobs must be a positive integer" >&2
    exit 2
    ;;
esac
if [[ "$(uname -m)" != "x86_64" ]]; then
  echo "the native MVP currently supports x86_64 only" >&2
  exit 2
fi
if [[ ! -f "$source_dir/MD5SUMS" ]]; then
  echo "verified source artefact not found at $source_dir" >&2
  exit 1
fi
(cd "$source_dir" && md5sum --check MD5SUMS)

build_user=xbee-lfs-native
work_root="$source_root/native-cross"
lfs_root="$work_root/rootfs"
build_root="$lfs_root/sources/work"
output_dir="$output_root/opt/xbee-lfs-native"
target="$(uname -m)-lfs-linux-gnu"

if ! id "$build_user" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash "$build_user"
fi

mkdir -p \
  "$lfs_root/etc" \
  "$lfs_root/var" \
  "$lfs_root/usr/bin" \
  "$lfs_root/usr/lib" \
  "$lfs_root/usr/sbin" \
  "$lfs_root/tools" \
  "$lfs_root/sources" \
  "$build_root" \
  "$output_dir"
for directory in bin lib sbin; do
  ln -sfn "usr/$directory" "$lfs_root/$directory"
done
mkdir -p "$lfs_root/lib64"

cp -a "$source_dir/." "$lfs_root/sources/"
chmod 1777 "$lfs_root/sources"
chown -R "$build_user:$build_user" "$work_root"

if [[ -e /tools && ! -L /tools ]]; then
  echo "/tools exists and is not a symbolic link; refusing to replace it" >&2
  exit 1
fi
ln -sfn "$lfs_root/tools" /tools
cleanup() {
  if [[ -L /tools && "$(readlink /tools)" == "$lfs_root/tools" ]]; then
    unlink /tools
  fi
}
trap cleanup EXIT

worker_script="$work_root/cross-worker.sh"
{
  printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail'
  sed -n '/^extract_source()/,$p' "$0"
} >"$worker_script"
chown "$build_user:$build_user" "$worker_script"
chmod 0755 "$worker_script"

sudo -u "$build_user" env -i \
  HOME="/home/$build_user" \
  TERM="${TERM:-dumb}" \
  PS1='(lfs) \\u:\\w\\$ ' \
  LFS="$lfs_root" \
  LFS_TGT="$target" \
  LC_ALL=POSIX \
  CONFIG_SITE=/dev/null \
  MAKEFLAGS="-j$jobs" \
  PATH="$lfs_root/tools/bin:/usr/bin" \
  SOURCES="$lfs_root/sources" \
  BUILD_ROOT="$build_root" \
  bash --noprofile --norc "$worker_script"

if [[ ! -x "$lfs_root/tools/bin/$target-gcc" ]]; then
  echo "cross GCC was not produced" >&2
  exit 1
fi
if [[ ! -e "$lfs_root/usr/lib/libc.so.6" ]]; then
  echo "target Glibc was not produced" >&2
  exit 1
fi

archive="$output_dir/cross-rootfs.tar.zst"
tar --xattrs --acls --numeric-owner --zstd \
  --exclude='./sources' \
  -C "$lfs_root" -cf "$archive" .
(
  cd "$output_dir"
  sha256sum "$(basename "$archive")" >"$(basename "$archive").sha256"
)

cat >"$output_dir/cross-metadata.yaml" <<EOF
schema-version: 1
lfs-book: "13.0"
stage: cross-toolchain
architecture: x86_64
target: "$target"
jobs: $jobs
packages:
  binutils: "2.46.0-pass1"
  gcc: "15.2.0-pass1"
  linux-headers: "6.18.10"
  glibc: "2.43"
  libstdc++: "15.2.0"
artefacts:
  rootfs: cross-rootfs.tar.zst
  checksum: cross-rootfs.tar.zst.sha256
EOF
exit 0

# Everything below this point runs as the unprivileged LFS build user.
extract_source() {
  local archive=$1
  local top
  top=$(tar -tf "$SOURCES/$archive" | sed -n '1{s@^\./@@;s@/.*@@;p;q}')
  if [[ -z "$top" ]]; then
    echo "cannot determine source directory for $archive" >&2
    exit 1
  fi
  rm -rf "$BUILD_ROOT/$top"
  tar -xf "$SOURCES/$archive" -C "$BUILD_ROOT"
  printf '%s\n' "$BUILD_ROOT/$top"
}

announce() {
  printf '\n===== LFS native: %s =====\n' "$1"
}

announce "Binutils 2.46.0 - pass 1"
package_dir=$(extract_source binutils-2.46.0.tar.xz)
mkdir "$package_dir/build"
(
  cd "$package_dir/build"
  ../configure \
    --prefix="$LFS/tools" \
    --with-sysroot="$LFS" \
    --target="$LFS_TGT" \
    --disable-nls \
    --enable-gprofng=no \
    --disable-werror \
    --enable-new-dtags \
    --enable-default-hash-style=gnu
  make
  make install
)

announce "GCC 15.2.0 - pass 1"
package_dir=$(extract_source gcc-15.2.0.tar.xz)
(
  cd "$package_dir"
  tar -xf "$SOURCES/mpfr-4.2.2.tar.xz"
  mv mpfr-4.2.2 mpfr
  tar -xf "$SOURCES/gmp-6.3.0.tar.xz"
  mv gmp-6.3.0 gmp
  tar -xf "$SOURCES/mpc-1.3.1.tar.gz"
  mv mpc-1.3.1 mpc
  sed -e '/m64=/s/lib64/lib/' -i.orig gcc/config/i386/t-linux64
  mkdir build
  cd build
  ../configure \
    --target="$LFS_TGT" \
    --prefix="$LFS/tools" \
    --with-glibc-version=2.43 \
    --with-sysroot="$LFS" \
    --with-newlib \
    --without-headers \
    --enable-default-pie \
    --enable-default-ssp \
    --disable-nls \
    --disable-shared \
    --disable-multilib \
    --disable-threads \
    --disable-libatomic \
    --disable-libgomp \
    --disable-libquadmath \
    --disable-libssp \
    --disable-libvtv \
    --disable-libstdcxx \
    --enable-languages=c,c++
  make
  make install
  cd ..
  cat gcc/limitx.h gcc/glimits.h gcc/limity.h > \
    "$(dirname "$("$LFS_TGT-gcc" -print-libgcc-file-name)")/include/limits.h"
)

announce "Linux 6.18.10 API headers"
package_dir=$(extract_source linux-6.18.10.tar.xz)
(
  cd "$package_dir"
  make mrproper
  make headers
  find usr/include -type f ! -name '*.h' -delete
  cp -rv usr/include "$LFS/usr"
)

announce "Glibc 2.43"
package_dir=$(extract_source glibc-2.43.tar.xz)
ln -sfn ../lib/ld-linux-x86-64.so.2 "$LFS/lib64/ld-linux-x86-64.so.2"
ln -sfn ../lib/ld-linux-x86-64.so.2 "$LFS/lib64/ld-lsb-x86-64.so.3"
(
  cd "$package_dir"
  patch -Np1 -i "$SOURCES/glibc-fhs-1.patch"
  mkdir build
  cd build
  echo "rootsbindir=/usr/sbin" >configparms
  ../configure \
    --prefix=/usr \
    --host="$LFS_TGT" \
    --build="$(../scripts/config.guess)" \
    --disable-nscd \
    libc_cv_slibdir=/usr/lib \
    --enable-kernel=5.4
  make
  make DESTDIR="$LFS" install
)
sed '/RTLDLIST=/s@/usr@@g' -i "$LFS/usr/bin/ldd"

announce "Glibc toolchain sanity check"
sanity_dir="$BUILD_ROOT/sanity"
mkdir -p "$sanity_dir"
(
  cd "$sanity_dir"
  echo 'int main(){}' | "$LFS_TGT-gcc" -x c - -v -Wl,--verbose &>dummy.log
  readelf -l a.out | grep -q ': /lib64/ld-linux-x86-64.so.2'
  grep -Eq "$LFS/lib.*/S?crt[1in].*succeeded" dummy.log
  grep -q "^ $LFS/usr/include" dummy.log
  grep -q "/lib.*/libc.so.6 " dummy.log
  grep -q found dummy.log
)

announce "Libstdc++ 15.2.0"
package_dir=$(extract_source gcc-15.2.0.tar.xz)
(
  cd "$package_dir"
  mkdir build
  cd build
  ../libstdc++-v3/configure \
    --host="$LFS_TGT" \
    --build="$(../config.guess)" \
    --prefix=/usr \
    --disable-multilib \
    --disable-nls \
    --disable-libstdcxx-pch \
    --with-gxx-include-dir="/tools/$LFS_TGT/include/c++/15.2.0"
  make
  make DESTDIR="$LFS" install
)
rm -f "$LFS"/usr/lib/lib{stdc++{,exp,fs},supc++}.la

announce "Cross-toolchain complete"
