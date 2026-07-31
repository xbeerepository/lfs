#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 5 ]]; then
  echo "usage: build-temporary-system.sh SOURCES CROSS_ARCHIVE JOBS SRC OUT" >&2
  exit 2
fi

source_dir=$1
cross_archive=$2
jobs=$3
source_root=$4
output_root=$5

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
if [[ ! -f "$cross_archive" ]]; then
  echo "cross-toolchain artefact not found: $cross_archive" >&2
  exit 1
fi
(cd "$source_dir" && md5sum --check MD5SUMS)

build_user=xbee-lfs-native
work_root="$source_root/native-temporary"
lfs_root="$work_root/rootfs"
build_root="$lfs_root/sources/work"
output_dir="$output_root/opt/xbee-lfs-native"
target="$(uname -m)-lfs-linux-gnu"

if ! id "$build_user" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash "$build_user"
fi

mkdir -p "$lfs_root" "$output_dir"
tar --zstd --xattrs --acls --numeric-owner -xf "$cross_archive" -C "$lfs_root"
mkdir -p "$lfs_root/sources" "$build_root"
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

worker_script="$work_root/temporary-worker.sh"
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
  CC="$target-gcc --sysroot=$lfs_root" \
  CXX="$target-g++ --sysroot=$lfs_root" \
  LC_ALL=POSIX \
  CONFIG_SITE=/dev/null \
  MAKEFLAGS="-j$jobs" \
  PATH="$lfs_root/tools/bin:/usr/bin" \
  SOURCES="$lfs_root/sources" \
  BUILD_ROOT="$build_root" \
  bash --noprofile --norc "$worker_script"

for command in bash cp find sed tar xz; do
  if [[ ! -x "$lfs_root/usr/bin/$command" ]]; then
    echo "temporary command was not produced: /usr/bin/$command" >&2
    exit 1
  fi
done

archive="$output_dir/temporary-rootfs.tar.zst"
tar --xattrs --acls --numeric-owner --zstd \
  --exclude='./sources' \
  -C "$lfs_root" -cf "$archive" .
(
  cd "$output_dir"
  sha256sum "$(basename "$archive")" >"$(basename "$archive").sha256"
)

cat >"$output_dir/temporary-metadata.yaml" <<EOF
schema-version: 1
lfs-book: "13.0"
stage: temporary-system
architecture: x86_64
target: "$target"
jobs: $jobs
packages:
  m4: "1.4.21"
  ncurses: "6.6"
  bash: "5.3"
  coreutils: "9.10"
  diffutils: "3.12"
  file: "5.46"
  findutils: "4.10.0"
  gawk: "5.3.2"
  grep: "3.12"
  gzip: "1.14"
  make: "4.4.1"
  patch: "2.8"
  sed: "4.9"
  tar: "1.35"
  xz: "5.8.2"
  binutils: "2.46.0-pass2"
  gcc: "15.2.0-pass2"
artefacts:
  rootfs: temporary-rootfs.tar.zst
  checksum: temporary-rootfs.tar.zst.sha256
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

configure_make_install() {
  local label=$1
  local archive=$2
  local config_guess=$3
  shift 3
  announce "$label"
  local package_dir
  package_dir=$(extract_source "$archive")
  local build_triplet=
  if [[ "$config_guess" != "-" ]]; then
    build_triplet=$("$package_dir/$config_guess")
  fi
  local args=()
  local arg
  for arg in "$@"; do
    args+=("${arg//@CONFIG_GUESS@/$build_triplet}")
  done
  (
    cd "$package_dir"
    ./configure "${args[@]}"
    make
    make DESTDIR="$LFS" install
  )
}

configure_make_install "M4 1.4.21" m4-1.4.21.tar.xz build-aux/config.guess \
  --prefix=/usr \
  --host="$LFS_TGT" \
  --build=@CONFIG_GUESS@

announce "Ncurses 6.6"
package_dir=$(extract_source ncurses-6.6.tar.gz)
(
  cd "$package_dir"
  mkdir build
  pushd build
  ../configure --prefix="$LFS/tools" AWK=gawk
  make -C include
  make -C progs tic
  install progs/tic "$LFS/tools/bin"
  popd
  ./configure \
    --prefix=/usr \
    --host="$LFS_TGT" \
    --build="$(./config.guess)" \
    --mandir=/usr/share/man \
    --with-manpage-format=normal \
    --with-shared \
    --without-normal \
    --with-cxx-shared \
    --without-debug \
    --without-ada \
    --disable-stripping \
    AWK=gawk
  make
  make DESTDIR="$LFS" install
)
ln -sfn libncursesw.so "$LFS/usr/lib/libncurses.so"
sed -e 's/^#if.*XOPEN.*$/#if 1/' -i "$LFS/usr/include/curses.h"

announce "Bash 5.3"
package_dir=$(extract_source bash-5.3.tar.gz)
(
  cd "$package_dir"
  ./configure \
    --prefix=/usr \
    --build="$(sh support/config.guess)" \
    --host="$LFS_TGT" \
    --without-bash-malloc
  make
  make DESTDIR="$LFS" install
)
ln -sfn bash "$LFS/bin/sh"

announce "Coreutils 9.10"
package_dir=$(extract_source coreutils-9.10.tar.xz)
(
  cd "$package_dir"
  ./configure \
    --prefix=/usr \
    --host="$LFS_TGT" \
    --build="$(build-aux/config.guess)" \
    --enable-install-program=hostname \
    --enable-no-install-program=kill,uptime
  make
  make DESTDIR="$LFS" install
)
mv "$LFS/usr/bin/chroot" "$LFS/usr/sbin"
mkdir -p "$LFS/usr/share/man/man8"
mv "$LFS/usr/share/man/man1/chroot.1" "$LFS/usr/share/man/man8/chroot.8"
sed -i 's/"1"/"8"/' "$LFS/usr/share/man/man8/chroot.8"

announce "Diffutils 3.12"
package_dir=$(extract_source diffutils-3.12.tar.xz)
(
  cd "$package_dir"
  ./configure \
    --prefix=/usr \
    --host="$LFS_TGT" \
    gl_cv_func_strcasecmp_works=y \
    --build="$(./build-aux/config.guess)"
  make
  make DESTDIR="$LFS" install
)

announce "File 5.46"
package_dir=$(extract_source file-5.46.tar.gz)
(
  cd "$package_dir"
  mkdir build
  pushd build
  ../configure --disable-bzlib --disable-libseccomp --disable-xzlib --disable-zlib
  make
  popd
  ./configure --prefix=/usr --host="$LFS_TGT" --build="$(./config.guess)"
  make FILE_COMPILE="$(pwd)/build/src/file"
  make DESTDIR="$LFS" install
)
rm -f "$LFS/usr/lib/libmagic.la"

configure_make_install "Findutils 4.10.0" findutils-4.10.0.tar.xz build-aux/config.guess \
  --prefix=/usr \
  --localstatedir=/var/lib/locate \
  --host="$LFS_TGT" \
  --build=@CONFIG_GUESS@

announce "Gawk 5.3.2"
package_dir=$(extract_source gawk-5.3.2.tar.xz)
(
  cd "$package_dir"
  sed -i 's/extras//' Makefile.in
  ./configure \
    --prefix=/usr \
    --host="$LFS_TGT" \
    --build="$(build-aux/config.guess)"
  make
  make DESTDIR="$LFS" install
)

configure_make_install "Grep 3.12" grep-3.12.tar.xz build-aux/config.guess \
  --prefix=/usr \
  --host="$LFS_TGT" \
  --build=@CONFIG_GUESS@

configure_make_install "Gzip 1.14" gzip-1.14.tar.xz - \
  --prefix=/usr \
  --host="$LFS_TGT"

configure_make_install "Make 4.4.1" make-4.4.1.tar.gz build-aux/config.guess \
  --prefix=/usr \
  --host="$LFS_TGT" \
  --build=@CONFIG_GUESS@

configure_make_install "Patch 2.8" patch-2.8.tar.xz build-aux/config.guess \
  --prefix=/usr \
  --host="$LFS_TGT" \
  --build=@CONFIG_GUESS@

configure_make_install "Sed 4.9" sed-4.9.tar.xz build-aux/config.guess \
  --prefix=/usr \
  --host="$LFS_TGT" \
  --build=@CONFIG_GUESS@

configure_make_install "Tar 1.35" tar-1.35.tar.xz build-aux/config.guess \
  --prefix=/usr \
  --host="$LFS_TGT" \
  --build=@CONFIG_GUESS@

announce "Xz 5.8.2"
package_dir=$(extract_source xz-5.8.2.tar.xz)
(
  cd "$package_dir"
  ./configure \
    --prefix=/usr \
    --host="$LFS_TGT" \
    --build="$(build-aux/config.guess)" \
    --disable-static \
    --docdir=/usr/share/doc/xz-5.8.2
  make
  make DESTDIR="$LFS" install
)
rm -f "$LFS/usr/lib/liblzma.la"

announce "Binutils 2.46.0 - pass 2"
package_dir=$(extract_source binutils-2.46.0.tar.xz)
(
  cd "$package_dir"
  sed '6031s/$add_dir//' -i ltmain.sh
  mkdir build
  cd build
  ../configure \
    --prefix=/usr \
    --build="$(../config.guess)" \
    --host="$LFS_TGT" \
    --disable-nls \
    --enable-shared \
    --enable-gprofng=no \
    --disable-werror \
    --enable-64-bit-bfd \
    --enable-new-dtags \
    --enable-default-hash-style=gnu
  make
  make DESTDIR="$LFS" install
)
rm -f "$LFS"/usr/lib/lib{bfd,ctf,ctf-nobfd,opcodes,sframe}.{a,la}

announce "GCC 15.2.0 - pass 2"
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
  sed '/thread_header =/s/@.*@/gthr-posix.h/' \
    -i libgcc/Makefile.in libstdc++-v3/include/Makefile.in
  mkdir build
  cd build
  ../configure \
    --build="$(../config.guess)" \
    --host="$LFS_TGT" \
    --target="$LFS_TGT" \
    --prefix=/usr \
    --with-build-sysroot="$LFS" \
    --enable-default-pie \
    --enable-default-ssp \
    --disable-nls \
    --disable-multilib \
    --disable-libatomic \
    --disable-libgomp \
    --disable-libquadmath \
    --disable-libsanitizer \
    --disable-libssp \
    --disable-libvtv \
    --enable-languages=c,c++ \
    LDFLAGS_FOR_TARGET="-L$PWD/$LFS_TGT/libgcc"
  make
  make DESTDIR="$LFS" install
)
ln -sfn gcc "$LFS/usr/bin/cc"

announce "Temporary system complete"
