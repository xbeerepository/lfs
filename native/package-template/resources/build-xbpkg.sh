#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 9 && $# -ne 10 ]]; then
  echo "usage: build-xbpkg.sh SOURCES ROOTFS NAME VERSION SOURCE DEPS JOBS SRC OUT [RECIPE]" >&2
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
recipe=${10:-}
tool_root=$(cd "$(dirname "$0")" && pwd)

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
if [[ -n "$recipe" && ! -f "$recipe" ]]; then
  echo "package recipe not found: $recipe" >&2
  exit 1
fi
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
builder_packages=/opt/xbee-lfs-packages
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

# XBee unpacks the artefacts of the directly declared package builders into
# /opt/xbee-lfs-packages. Overlay their verified payloads on the bootstrap
# final-system so this package is built against those artefacts rather than
# against the historical copies bundled in the bootstrap rootfs.
shopt -s nullglob
dependency_archives=("$builder_packages"/*.xbpkg.tar.zst)
shopt -u nullglob
for dependency_archive in "${dependency_archives[@]}"; do
  dependency_checksum="$dependency_archive.sha256"
  [[ -f "$dependency_checksum" ]] || {
    echo "dependency checksum not found: $dependency_checksum" >&2
    exit 1
  }
  expected=$(awk 'NR == 1 {print $1}' "$dependency_checksum")
  actual=$(sha256sum "$dependency_archive" | awk '{print $1}')
  [[ -n "$expected" && "$expected" == "$actual" ]] || {
    echo "dependency package checksum mismatch: $dependency_archive" >&2
    exit 1
  }

  dependency_root=$(mktemp -d "$work_root/dependency.XXXXXX")
  tar --zstd -xf "$dependency_archive" -C "$dependency_root"
  dependency_manifest="$dependency_root/.XBPKG/manifest.yaml"
  [[ -f "$dependency_manifest" && -d "$dependency_root/rootfs" ]] || {
    echo "invalid dependency package layout: $dependency_archive" >&2
    exit 1
  }
  dependency_name=$(sed -n \
    's/^name:[[:space:]]*"\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' \
    "$dependency_manifest")
  [[ "$dependency_name" =~ ^[a-z0-9][a-z0-9+._-]*$ ]] || {
    echo "invalid dependency package identity: $dependency_archive" >&2
    exit 1
  }
  while IFS= read -r dependency_path; do
    [[ "$dependency_path" == /* &&
       "$dependency_path" != *"/../"* ]] || {
      echo "unsafe dependency package path: $dependency_path" >&2
      exit 1
    }
    rm -f "$rootfs$dependency_path"
  done <"$dependency_root/.XBPKG/files"
  # Preserve the merged-/usr links from the bootstrap rootfs when an older
  # package payload contains a real top-level compatibility directory.
  for merged_usr_dir in bin sbin lib lib64; do
    if [[ -L "$rootfs/$merged_usr_dir" &&
          -d "$dependency_root/rootfs/$merged_usr_dir" &&
          ! -L "$dependency_root/rootfs/$merged_usr_dir" ]]; then
      cp -a "$dependency_root/rootfs/$merged_usr_dir/." \
        "$rootfs/$merged_usr_dir/"
      rm -rf "$dependency_root/rootfs/$merged_usr_dir"
    fi
  done
  cp -a "$dependency_root/rootfs/." "$rootfs/"
  rm -rf "$dependency_root"
done

mkdir -p "$rootfs/sources" "$stage"
if [[ "$package_name" == ca-certificates ]]; then
  mkdir -p "$build_dir"
  cp "$sources/$source_name" "$build_dir/ca-certificates.crt"
elif [[ "$source_name" == *.zip ]]; then
  mkdir -p "$build_dir"
  cp "$sources/$source_name" "$rootfs/sources/"
  chroot "$rootfs" /usr/bin/unzip -q \
    "/sources/$source_name" -d "/sources/xbpkg-$package_name"
else
  tar -xf "$sources/$source_name" -C "$rootfs/sources"
  source_directory=$(tar -tf "$sources/$source_name" | awk '
    {
      sub(/^\.\//, "")
      if (!found && $0 ~ /^[^/]+\//) {
        sub(/\/.*/, "")
        print
        found = 1
      }
    }
  ')
  [[ "$source_directory" =~ ^[A-Za-z0-9][A-Za-z0-9+._~-]*$ &&
     -d "$rootfs/sources/$source_directory" ]] || {
    echo "invalid or missing archive root directory: $source_name" >&2
    exit 1
  }
  mv "$rootfs/sources/$source_directory" "$build_dir"
fi

if [[ -n "$recipe" ]]; then
  install -m 0755 "$recipe" "$rootfs/sources/xbpkg-recipe.sh"
  find "$sources" -maxdepth 1 -type f -name '*.patch' \
    -exec cp -t "$rootfs/sources" {} +
fi

case "$package_name" in
  linux-kernel|linux-modules)
    cp "$tool_root/kernel-x86_64.config" "$rootfs/sources/"
    ;;
  glibc)
    cp "$sources/glibc-fhs-1.patch" "$rootfs/sources/"
    cp "$sources/tzdata2025c.tar.gz" "$rootfs/sources/"
    ;;
  sqlite)
    cp "$sources/sqlite-doc-3510200.tar.xz" "$rootfs/sources/"
    ;;
  python)
    cp "$sources/python-3.14.3-docs-html.tar.bz2" "$rootfs/sources/"
    ;;
  kbd)
    cp "$sources/kbd-2.9.0-backspace-1.patch" "$rootfs/sources/"
    ;;
  tcl)
    cp "$sources/tcl8.6.17-html.tar.gz" "$rootfs/sources/"
    ;;
  expect)
    cp "$sources/expect-5.45.4-gcc15-1.patch" "$rootfs/sources/"
    ;;
  coreutils)
    cp "$sources/coreutils-9.10-i18n-1.patch" "$rootfs/sources/"
    ;;
  systemd)
    cp "$sources/systemd-man-pages-259.1.tar.xz" "$rootfs/sources/"
    ;;
  rustc)
    cp "$sources/rustc-1.96.0-x86_64-unknown-linux-gnu.tar.xz" \
      "$sources/rust-std-1.96.0-x86_64-unknown-linux-gnu.tar.xz" \
      "$sources/cargo-1.96.0-x86_64-unknown-linux-gnu.tar.xz" \
      "$rootfs/sources/"
    ;;
  cargo-c)
    cp "$sources/cargo-c-0.10.24-Cargo.lock" \
      "$sources/cargo-c-0.10.24-crates.tar.zst" \
      "$rootfs/sources/"
    ;;
  librsvg)
    cp "$sources/librsvg-2.62.3-Cargo.lock" \
      "$sources/librsvg-2.62.3-crates.tar.zst" \
      "$rootfs/sources/"
    ;;
  libcdio)
    cp "$sources/libcdio-paranoia-10.2+2.0.2.tar.bz2" "$rootfs/sources/"
    ;;
  audacious)
    cp "$sources/audacious-plugins-$package_version.tar.bz2" \
      "$rootfs/sources/"
    ;;
  speex)
    cp "$sources/speexdsp-1.2.1.tar.gz" "$rootfs/sources/"
    ;;
  sassc)
    cp "$sources/libsass-3.6.6.tar.gz" "$rootfs/sources/"
    ;;
  gst-plugins-rs)
    cp "$(dirname "$recipe")/cargo-vendor-1.28.1.tar.zst" "$rootfs/sources/"
    ;;
esac

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

if [[ -n "$recipe" ]]; then
  chroot "$rootfs" /usr/bin/env -i \
    HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
    PACKAGE_NAME="$package_name" PACKAGE_VERSION="$package_version" \
    JOBS="$jobs" SOURCE_DIR="/sources/xbpkg-$package_name" STAGE=/stage \
    bash -lc 'cd "$SOURCE_DIR" && /sources/xbpkg-recipe.sh'
else
case "$package_name" in
  ca-certificates)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "install -Dm 0644 \
          /sources/xbpkg-ca-certificates/ca-certificates.crt \
          /stage/etc/ssl/certs/ca-certificates.crt &&
        install -d /stage/etc/pki/tls/certs &&
        ln -sfn /etc/ssl/certs/ca-certificates.crt \
          /stage/etc/ssl/cert.pem &&
        ln -sfn /etc/ssl/certs/ca-certificates.crt \
          /stage/etc/pki/tls/certs/ca-bundle.crt"
    ;;
  wget)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-wget &&
        ./configure --prefix=/usr --sysconfdir=/etc \
          --with-ssl=openssl --disable-static --disable-nls \
          --without-libidn --without-libpsl &&
        make -j$jobs &&
        make DESTDIR=/stage install"
    ;;
  curl)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-curl &&
        ./configure --prefix=/usr \
          --with-openssl \
          --with-ca-bundle=/etc/ssl/certs/ca-certificates.crt \
          --disable-static --enable-ares \
          --with-libpsl --with-libidn2 --with-brotli \
          --with-nghttp2 --without-nghttp3 --without-ngtcp2 \
          --with-libssh2 --with-zstd &&
        make -j$jobs &&
        make DESTDIR=/stage install"
    ;;
  dhcpcd)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-dhcpcd &&
        ./configure --prefix=/usr --sysconfdir=/etc \
          --libexecdir=/usr/lib/dhcpcd \
          --dbdir=/var/lib/dhcpcd --runstatedir=/run \
          --disable-privsep &&
        make -j$jobs &&
        make DESTDIR=/stage install &&
        install -d /stage/usr/lib/systemd/system &&
        printf '%s\n' \
          '[Unit]' \
          'Description=DHCP client daemon' \
          'After=network-pre.target' \
          'Before=network.target' \
          'Wants=network.target' \
          '' \
          '[Service]' \
          'Type=forking' \
          'ExecStart=/usr/sbin/dhcpcd -q -b' \
          'ExecStop=/usr/sbin/dhcpcd -x' \
          '' \
          '[Install]' \
          'WantedBy=multi-user.target' \
          > /stage/usr/lib/systemd/system/dhcpcd.service"
    ;;
  rsync)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-rsync &&
        ./configure --prefix=/usr \
          --disable-xxhash --without-included-zlib &&
        make -j$jobs &&
        make DESTDIR=/stage install"
    ;;
  linux-headers)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-linux-headers &&
        make mrproper &&
        make headers &&
        find usr/include -type f ! -name '*.h' -delete &&
        install -d /stage/usr/include &&
        cp -a usr/include/. /stage/usr/include/"
    ;;
  linux-kernel)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-linux-kernel &&
        make mrproper &&
        make defconfig &&
        scripts/kconfig/merge_config.sh \
          -m .config ../kernel-x86_64.config &&
        make olddefconfig &&
        make -j$jobs bzImage &&
        install -D -m 0644 arch/x86/boot/bzImage \
          /stage/boot/vmlinuz-$package_version-xbee-lfs &&
        install -m 0644 System.map \
          /stage/boot/System.map-$package_version-xbee-lfs &&
        install -m 0644 .config \
          /stage/boot/config-$package_version-xbee-lfs"
    ;;
  linux-modules)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-linux-modules &&
        make mrproper &&
        make defconfig &&
        scripts/kconfig/merge_config.sh \
          -m .config ../kernel-x86_64.config &&
        make olddefconfig &&
        make -j$jobs &&
        make INSTALL_MOD_PATH=/stage modules_install &&
        if [[ -d /stage/lib/modules ]]; then
          install -d /stage/usr/lib &&
          mv /stage/lib/modules /stage/usr/lib/ &&
          rmdir /stage/lib
        fi &&
        rm -f /stage/usr/lib/modules/$package_version/build \
          /stage/usr/lib/modules/$package_version/source"
    ;;
  openssh)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-openssh &&
        ./configure \
          --prefix=/usr \
          --sysconfdir=/etc/ssh \
          --with-privsep-path=/var/lib/sshd \
          --with-privsep-user=nobody \
          --with-pid-dir=/run \
          --with-default-path=/usr/local/bin:/usr/bin \
          --with-superuser-path=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin \
          --without-pam &&
        make -j$jobs &&
        make DESTDIR=/stage install &&
        rm -f /stage/etc/ssh/ssh_host_*_key \
          /stage/etc/ssh/ssh_host_*_key.pub &&
        install -d /stage/var/lib/sshd &&
        touch /stage/var/lib/sshd/.keep &&
        install -d /stage/usr/lib/systemd/system &&
        printf '%s\n' \
          '[Unit]' \
          'Description=OpenSSH server daemon' \
          'After=network.target' \
          '' \
          '[Service]' \
          'Type=simple' \
          'ExecStartPre=/usr/bin/ssh-keygen -A' \
          'ExecStart=/usr/sbin/sshd -D' \
          'ExecReload=/bin/kill -HUP \$MAINPID' \
          'KillMode=process' \
          'Restart=on-failure' \
          '' \
          '[Install]' \
          'WantedBy=multi-user.target' \
          >/stage/usr/lib/systemd/system/sshd.service"
    ;;
  sudo)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-sudo &&
        ./configure \
          --prefix=/usr \
          --libexecdir=/usr/lib \
          --with-secure-path=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin \
          --with-env-editor \
          --without-pam \
          --without-sendmail &&
        make -j$jobs &&
        make DESTDIR=/stage install &&
        chmod 4755 /stage/usr/bin/sudo"
    ;;
  glibc)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      LFS_TIMEZONE=Europe/Paris \
      bash -lc "cd /sources/xbpkg-glibc &&
        patch -Np1 -i ../glibc-fhs-1.patch &&
        mkdir -p build &&
        cd build &&
        printf '%s\n' 'rootsbindir=/usr/sbin' >configparms &&
        ../configure --prefix=/usr \
          --disable-werror \
          --disable-nscd \
          libc_cv_slibdir=/usr/lib \
          --enable-stack-protector=strong \
          --enable-kernel=5.4 &&
        make -j$jobs &&
        sed '/test-installation/s@\\\$(PERL)@echo not running@' \
          -i ../Makefile &&
        make DESTDIR=/stage install &&
        sed '/RTLDLIST=/s@/usr@@g' -i /stage/usr/bin/ldd &&
        install -d /stage/lib64 &&
        ln -sfn ../usr/lib/ld-linux-x86-64.so.2 \
          /stage/lib64/ld-linux-x86-64.so.2 &&
        ln -sfn ../usr/lib/ld-linux-x86-64.so.2 \
          /stage/lib64/ld-lsb-x86-64.so.3 &&
        make DESTDIR=/stage localedata/install-locales &&
        cd .. &&
        tar -xf ../tzdata2025c.tar.gz &&
        zoneinfo=/stage/usr/share/zoneinfo &&
        install -d \"\$zoneinfo/posix\" \"\$zoneinfo/right\" &&
        for tz in etcetera southamerica northamerica europe africa \
          antarctica asia australasia backward; do
          /stage/usr/sbin/zic -L /dev/null \
            -d \"\$zoneinfo\" \"\$tz\" &&
          /stage/usr/sbin/zic -L /dev/null \
            -d \"\$zoneinfo/posix\" \"\$tz\" &&
          /stage/usr/sbin/zic -L leapseconds \
            -d \"\$zoneinfo/right\" \"\$tz\"
        done &&
        cp zone.tab zone1970.tab iso3166.tab \"\$zoneinfo\" &&
        /stage/usr/sbin/zic -d \"\$zoneinfo\" \
          -p America/New_York &&
        install -d /stage/etc/ld.so.conf.d &&
        ln -sfn /usr/share/zoneinfo/\$LFS_TIMEZONE \
          /stage/etc/localtime &&
        printf '%s\n' \
          '# Begin /etc/nsswitch.conf' \
          '' \
          'passwd: files systemd' \
          'group: files systemd' \
          'shadow: files systemd' \
          '' \
          'hosts: mymachines resolve [!UNAVAIL=return] files myhostname dns' \
          'networks: files' \
          '' \
          'protocols: files' \
          'services: files' \
          'ethers: files' \
          'rpc: files' \
          '' \
          '# End /etc/nsswitch.conf' \
          >/stage/etc/nsswitch.conf &&
        printf '%s\n' \
          '# Begin /etc/ld.so.conf' \
          '/usr/local/lib' \
          '/opt/lib' \
          '' \
          'include /etc/ld.so.conf.d/*.conf' \
          >/stage/etc/ld.so.conf"
    ;;
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
  lz4)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-lz4 &&
        make -j$jobs BUILD_STATIC=no PREFIX=/usr &&
        make BUILD_STATIC=no PREFIX=/usr DESTDIR=/stage install"
    ;;
  attr)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-attr &&
        ./configure --prefix=/usr --disable-static \
          --sysconfdir=/etc \
          --docdir=/usr/share/doc/attr-$package_version &&
        make -j$jobs &&
        make DESTDIR=/stage install"
    ;;
  acl)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-acl &&
        ./configure --prefix=/usr --disable-static \
          --docdir=/usr/share/doc/acl-$package_version &&
        make -j$jobs &&
        make DESTDIR=/stage install"
    ;;
  libpipeline)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-libpipeline &&
        ./configure --prefix=/usr &&
        make -j$jobs &&
        make DESTDIR=/stage install"
    ;;
  man-db)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-man-db &&
        ./configure --prefix=/usr \
          --docdir=/usr/share/doc/man-db-$package_version \
          --sysconfdir=/etc \
          --disable-setuid \
          --enable-cache-owner=bin \
          --with-browser=/usr/bin/lynx \
          --with-vgrind=/usr/bin/vgrind \
          --with-grap=/usr/bin/grap &&
        make -j$jobs &&
        make DESTDIR=/stage install"
    ;;
  ncurses)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-ncurses &&
        ./configure --prefix=/usr \
          --mandir=/usr/share/man \
          --with-shared \
          --without-debug \
          --without-normal \
          --with-cxx-shared \
          --enable-pc-files \
          --with-pkg-config-libdir=/usr/lib/pkgconfig &&
        make -j$jobs &&
        make DESTDIR=/stage install &&
        sed -e 's/^#if.*XOPEN.*$/#if 1/' \
          -i /stage/usr/include/curses.h &&
        for lib in ncurses form panel menu; do
          ln -sfn lib\${lib}w.so /stage/usr/lib/lib\${lib}.so
          ln -sfn \${lib}w.pc /stage/usr/lib/pkgconfig/\${lib}.pc
        done &&
        ln -sfn libncursesw.so /stage/usr/lib/libcurses.so &&
        mkdir -p /stage/usr/share/doc/ncurses-$package_version &&
        cp -a doc/. /stage/usr/share/doc/ncurses-$package_version/"
    ;;
  readline)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-readline &&
        sed -i '/MV.*old/d' Makefile.in &&
        sed -i '/{OLDSUFF}/c:' support/shlib-install &&
        sed -i 's/-Wl,-rpath,[^ ]*//' support/shobj-conf &&
        sed -e '270a\\
     else\\
       chars_avail = 1;' \
          -e '288i\\   result = -1;' \
          -i.orig input.c &&
        ./configure --prefix=/usr --disable-static --with-curses \
          --docdir=/usr/share/doc/readline-$package_version &&
        make -j$jobs SHLIB_LIBS='-lncursesw' &&
        make DESTDIR=/stage install &&
        install -d /stage/usr/share/doc/readline-$package_version &&
        install -m 0644 doc/*.ps doc/*.pdf doc/*.html doc/*.dvi \
          /stage/usr/share/doc/readline-$package_version/"
    ;;
  pcre2)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-pcre2 &&
        ./configure --prefix=/usr \
          --docdir=/usr/share/doc/pcre2-$package_version \
          --enable-unicode \
          --enable-jit \
          --enable-pcre2-16 \
          --enable-pcre2-32 \
          --enable-pcre2grep-libz \
          --enable-pcre2grep-libbz2 \
          --enable-pcre2test-libreadline \
          --disable-static &&
        make -j$jobs &&
        make DESTDIR=/stage install"
    ;;
  libcap)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-libcap &&
        sed -i '/install -m.*STA/d' libcap/Makefile &&
        make -j$jobs prefix=/usr lib=lib &&
        make prefix=/usr lib=lib DESTDIR=/stage install"
    ;;
  libelf)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-libelf &&
        ./configure --prefix=/usr \
          --disable-debuginfod \
          --enable-libdebuginfod=dummy &&
        make -j$jobs -C lib &&
        make -j$jobs -C libelf &&
        make -C libelf DESTDIR=/stage install &&
        install -d /stage/usr/lib/pkgconfig &&
        install -m 0644 config/libelf.pc /stage/usr/lib/pkgconfig/ &&
        rm -f /stage/usr/lib/libelf.a"
    ;;
  gmp)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-gmp &&
        sed -i '/long long t1;/,+1s/()/(...)/' configure &&
        ./configure --prefix=/usr \
          --enable-cxx \
          --disable-static \
          --docdir=/usr/share/doc/gmp-$package_version &&
        make -j$jobs &&
        make -j$jobs html &&
        make DESTDIR=/stage install &&
        make DESTDIR=/stage install-html"
    ;;
  mpfr)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-mpfr &&
        ./configure --prefix=/usr \
          --disable-static \
          --enable-thread-safe \
          --docdir=/usr/share/doc/mpfr-$package_version &&
        make -j$jobs &&
        make -j$jobs html &&
        make DESTDIR=/stage install &&
        make DESTDIR=/stage install-html"
    ;;
  mpc)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-mpc &&
        ./configure --prefix=/usr \
          --disable-static \
          --docdir=/usr/share/doc/mpc-$package_version &&
        make -j$jobs &&
        make -j$jobs html &&
        make DESTDIR=/stage install &&
        make DESTDIR=/stage install-html"
    ;;
  m4)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-m4 &&
        ./configure --prefix=/usr &&
        make -j$jobs &&
        make DESTDIR=/stage install"
    ;;
  bison)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-bison &&
        ./configure --prefix=/usr \
          --docdir=/usr/share/doc/bison-$package_version &&
        make -j$jobs &&
        make DESTDIR=/stage install"
    ;;
  flex)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-flex &&
        ./configure --prefix=/usr \
          --disable-static \
          --docdir=/usr/share/doc/flex-$package_version &&
        make -j$jobs &&
        make DESTDIR=/stage install &&
        ln -sfn flex /stage/usr/bin/lex &&
        ln -sfn flex.1 /stage/usr/share/man/man1/lex.1"
    ;;
  autoconf)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-autoconf &&
        ./configure --prefix=/usr &&
        make -j$jobs &&
        make DESTDIR=/stage install"
    ;;
  automake)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-automake &&
        ./configure --prefix=/usr \
          --docdir=/usr/share/doc/automake-$package_version &&
        make -j$jobs &&
        make DESTDIR=/stage install"
    ;;
  libtool)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-libtool &&
        ./configure --prefix=/usr &&
        make -j$jobs &&
        make DESTDIR=/stage install &&
        rm -f /stage/usr/lib/libltdl.a"
    ;;
  pkgconf)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-pkgconf &&
        ./configure --prefix=/usr \
          --disable-static \
          --docdir=/usr/share/doc/pkgconf-$package_version &&
        make -j$jobs &&
        make DESTDIR=/stage install &&
        ln -sfn pkgconf /stage/usr/bin/pkg-config &&
        ln -sfn pkgconf.1 /stage/usr/share/man/man1/pkg-config.1"
    ;;
  binutils)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-binutils &&
        mkdir -p build &&
        cd build &&
        ../configure --prefix=/usr \
          --sysconfdir=/etc \
          --enable-ld=default \
          --enable-plugins \
          --enable-shared \
          --disable-werror \
          --enable-64-bit-bfd \
          --enable-new-dtags \
          --with-system-zlib \
          --enable-default-hash-style=gnu &&
        make -j$jobs tooldir=/usr &&
        make tooldir=/usr DESTDIR=/stage install &&
        rm -f /stage/usr/lib/lib{bfd,ctf,ctf-nobfd,gprofng,opcodes,sframe}.a &&
        rm -rf /stage/usr/share/doc/gprofng"
    ;;
  gcc)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-gcc &&
        sed -i 's/char [*]q/const &/' libgomp/affinity-fmt.c &&
        case \$(uname -m) in
          x86_64)
            sed -e '/m64=/s/lib64/lib/' \
              -i.orig gcc/config/i386/t-linux64
            ;;
        esac &&
        mkdir -p build &&
        cd build &&
        ../configure --prefix=/usr \
          LD=ld \
          --enable-languages=c,c++ \
          --enable-default-pie \
          --enable-default-ssp \
          --enable-host-pie \
          --disable-multilib \
          --disable-bootstrap \
          --disable-fixincludes \
          --with-system-zlib &&
        make -j$jobs &&
        make DESTDIR=/stage install &&
        target=\$(gcc -dumpmachine) &&
        chown -R root:root \
          /stage/usr/lib/gcc/\$target/$package_version/include \
          /stage/usr/lib/gcc/\$target/$package_version/include-fixed &&
        ln -sfn ../bin/cpp /stage/usr/lib/cpp &&
        ln -sfn gcc.1 /stage/usr/share/man/man1/cc.1 &&
        mkdir -p /stage/usr/lib/bfd-plugins &&
        ln -sfn ../../libexec/gcc/\$target/$package_version/liblto_plugin.so \
          /stage/usr/lib/bfd-plugins/ &&
        mkdir -p /stage/usr/share/gdb/auto-load/usr/lib &&
        find /stage/usr/lib -maxdepth 1 -type f -name '*gdb.py' \
          -exec mv -t /stage/usr/share/gdb/auto-load/usr/lib {} +"
    ;;
  libffi)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-libffi &&
        ./configure --prefix=/usr \
          --disable-static \
          --with-gcc-arch=native &&
        make -j$jobs &&
        make DESTDIR=/stage install"
    ;;
  expat)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-expat &&
        ./configure --prefix=/usr \
          --disable-static \
          --docdir=/usr/share/doc/expat-$package_version &&
        make -j$jobs &&
        make DESTDIR=/stage install &&
        install -m 0644 doc/*.html doc/*.css \
          /stage/usr/share/doc/expat-$package_version/"
    ;;
  gdbm)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-gdbm &&
        ./configure --prefix=/usr \
          --disable-static \
          --enable-libgdbm-compat &&
        make -j$jobs &&
        make DESTDIR=/stage install"
    ;;
  openssl)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-openssl &&
        ./config --prefix=/usr \
          --openssldir=/etc/ssl \
          --libdir=lib \
          shared \
          zlib-dynamic &&
        make -j$jobs &&
        sed -i '/INSTALL_LIBS/s/libcrypto.a libssl.a//' Makefile &&
        make DESTDIR=/stage MANSUFFIX=ssl install &&
        mv /stage/usr/share/doc/openssl \
          /stage/usr/share/doc/openssl-$package_version &&
        cp -a doc/. /stage/usr/share/doc/openssl-$package_version/"
    ;;
  sqlite)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-sqlite &&
        tar -xf ../sqlite-doc-3510200.tar.xz &&
        ./configure --prefix=/usr \
          --disable-static \
          --enable-fts4 \
          --enable-fts5 \
          CPPFLAGS='-D SQLITE_ENABLE_COLUMN_METADATA=1 -D SQLITE_ENABLE_UNLOCK_NOTIFY=1 -D SQLITE_ENABLE_DBSTAT_VTAB=1 -D SQLITE_SECURE_DELETE=1' &&
        make -j$jobs LDFLAGS.rpath='' &&
        make DESTDIR=/stage install &&
        install -d /stage/usr/share/doc/sqlite-$package_version &&
        cp -a sqlite-doc-3510200/. \
          /stage/usr/share/doc/sqlite-$package_version/"
    ;;
  python)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-python &&
        ./configure --prefix=/usr \
          --enable-shared \
          --with-system-expat \
          --enable-optimizations \
          --without-static-libpython &&
        make -j$jobs &&
        make DESTDIR=/stage install &&
        install -d /stage/etc &&
        printf '%s\n' '[global]' \
          'root-user-action = ignore' \
          'disable-pip-version-check = true' \
          > /stage/etc/pip.conf &&
        install -d /stage/usr/share/doc/python-$package_version/html &&
        tar --strip-components=1 \
          --no-same-owner \
          --no-same-permissions \
          -C /stage/usr/share/doc/python-$package_version/html \
          -xf ../python-3.14.3-docs-html.tar.bz2"
    ;;
  flit-core)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-flit-core &&
        python3 -m pip wheel -w dist \
          --no-cache-dir --no-build-isolation --no-deps . &&
        python3 -m pip install --root=/stage --prefix=/usr \
          --ignore-installed --no-deps --no-index --find-links dist flit_core"
    ;;
  packaging)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-packaging &&
        python3 -m pip wheel -w dist \
          --no-cache-dir --no-build-isolation --no-deps . &&
        python3 -m pip install --root=/stage --prefix=/usr \
          --ignore-installed --no-deps --no-index --find-links dist packaging"
    ;;
  markupsafe)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-markupsafe &&
        python3 -m pip wheel -w dist \
          --no-cache-dir --no-build-isolation --no-deps . &&
        python3 -m pip install --root=/stage --prefix=/usr \
          --ignore-installed --no-deps --no-index --find-links dist MarkupSafe"
    ;;
  jinja2)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-jinja2 &&
        python3 -m pip wheel -w dist \
          --no-cache-dir --no-build-isolation --no-deps . &&
        python3 -m pip install --root=/stage --prefix=/usr \
          --ignore-installed --no-deps --no-index --find-links dist Jinja2"
    ;;
  meson)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-meson &&
        python3 -m pip wheel -w dist \
          --no-cache-dir --no-build-isolation --no-deps . &&
        python3 -m pip install --root=/stage --prefix=/usr \
          --ignore-installed --no-deps --no-index --find-links dist meson &&
        install -Dm 0644 data/shell-completions/bash/meson \
          /stage/usr/share/bash-completion/completions/meson &&
        install -Dm 0644 data/shell-completions/zsh/_meson \
          /stage/usr/share/zsh/site-functions/_meson"
    ;;
  ninja)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-ninja &&
        sed -i '/int Guess/a\\
  int   j = 0;\\
  char* jobs = getenv( \"NINJAJOBS\" );\\
  if ( jobs != NULL ) j = atoi( jobs );\\
  if ( j > 0 ) return j;\\
' src/ninja.cc &&
        NINJAJOBS=$jobs python3 configure.py --bootstrap --verbose &&
        install -Dm 0755 ninja /stage/usr/bin/ninja &&
        install -Dm 0644 misc/bash-completion \
          /stage/usr/share/bash-completion/completions/ninja &&
        install -Dm 0644 misc/zsh-completion \
          /stage/usr/share/zsh/site-functions/_ninja"
    ;;
  bc)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-bc &&
        CC='gcc -std=c99' ./configure --prefix=/usr -G -O3 -r &&
        make -j$jobs &&
        make DESTDIR=/stage install"
    ;;
  gperf)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-gperf &&
        ./configure --prefix=/usr \
          --docdir=/usr/share/doc/gperf-$package_version &&
        make -j$jobs &&
        make DESTDIR=/stage install"
    ;;
  libxcrypt)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-libxcrypt &&
        sed -i '/strchr/s/const//' lib/crypt-{sm3,gost}-yescrypt.c &&
        ./configure --prefix=/usr \
          --enable-hashes=strong,glibc \
          --enable-obsolete-api=no \
          --disable-static \
          --disable-failure-tokens &&
        make -j$jobs &&
        make DESTDIR=/stage install"
    ;;
  less)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-less &&
        ./configure --prefix=/usr --sysconfdir=/etc &&
        make -j$jobs &&
        make DESTDIR=/stage install"
    ;;
  kmod)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-kmod &&
        mkdir -p build &&
        cd build &&
        meson setup --prefix=/usr .. \
          --buildtype=release \
          -D manpages=false &&
        ninja -j$jobs &&
        DESTDIR=/stage ninja install"
    ;;
  procps-ng)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-procps-ng &&
        ./configure --prefix=/usr \
          --docdir=/usr/share/doc/procps-ng-$package_version \
          --disable-static \
          --disable-kill \
          --enable-watch8bit \
          --with-systemd &&
        make -j$jobs &&
        make DESTDIR=/stage install"
    ;;
  e2fsprogs)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-e2fsprogs &&
        mkdir -p build &&
        cd build &&
        ../configure --prefix=/usr \
          --sysconfdir=/etc \
          --enable-elf-shlibs \
          --disable-libblkid \
          --disable-libuuid \
          --disable-uuidd \
          --disable-fsck &&
        make -j$jobs &&
        make DESTDIR=/stage install &&
        rm -f /stage/usr/lib/{libcom_err,libe2p,libext2fs,libss}.a &&
        gunzip /stage/usr/share/info/libext2fs.info.gz &&
        makeinfo -o doc/com_err.info ../lib/et/com_err.texinfo &&
        install -m 0644 doc/com_err.info /stage/usr/share/info/ &&
        sed 's/metadata_csum_seed,//' -i /stage/etc/mke2fs.conf"
    ;;
  shadow)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-shadow &&
        sed -i 's/groups\$(EXEEXT) //' src/Makefile.in &&
        find man -name Makefile.in -exec sed -i 's/groups\\.1 / /' {} \\; &&
        find man -name Makefile.in -exec sed -i 's/getspnam\\.3 / /' {} \\; &&
        find man -name Makefile.in -exec sed -i 's/passwd\\.5 / /' {} \\; &&
        sed -e 's:#ENCRYPT_METHOD DES:ENCRYPT_METHOD YESCRYPT:' \
          -e 's:/var/spool/mail:/var/mail:' \
          -e '/PATH=/{s@/sbin:@@;s@/bin:@@}' \
          -i etc/login.defs &&
        ./configure --sysconfdir=/etc \
          --disable-static \
          --with-bcrypt \
          --with-yescrypt \
          --without-libbsd \
          --disable-logind \
          --with-group-name-max-length=32 &&
        make -j$jobs &&
        make exec_prefix=/usr DESTDIR=/stage install &&
        make -C man DESTDIR=/stage install-man"
    ;;
  iproute2)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-iproute2 &&
        sed -i /ARPD/d Makefile &&
        rm -f man/man8/arpd.8 &&
        make -j$jobs NETNS_RUN_DIR=/run/netns &&
        make DESTDIR=/stage SBINDIR=/usr/sbin install &&
        install -Dm 0644 COPYING \
          /stage/usr/share/doc/iproute2-$package_version/COPYING &&
        install -m 0644 README* \
          /stage/usr/share/doc/iproute2-$package_version/"
    ;;
  inetutils)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-inetutils &&
        sed -i 's/def HAVE_TERMCAP_TGETENT/ 1/' telnet/telnet.c &&
        inetutils_cv_path_procnet_dev=/proc/net/dev \
        ./configure --prefix=/usr \
          --bindir=/usr/bin \
          --localstatedir=/var \
          --disable-logger \
          --disable-whois \
          --disable-rcp \
          --disable-rexec \
          --disable-rlogin \
          --disable-rsh \
          --disable-servers &&
        make -j$jobs &&
        make DESTDIR=/stage install &&
        install -d /stage/usr/sbin &&
        mv /stage/usr/bin/ifconfig /stage/usr/sbin/"
    ;;
  kbd)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-kbd &&
        patch -Np1 -i ../kbd-2.9.0-backspace-1.patch &&
        sed -i '/RESIZECONS_PROGS=/s/yes/no/' configure &&
        sed -i 's/resizecons.8 //' docs/man/man8/Makefile.in &&
        ./configure --prefix=/usr --disable-vlock &&
        make -j$jobs &&
        make DESTDIR=/stage install &&
        install -d /stage/usr/share/doc/kbd-$package_version &&
        cp -a docs/doc/. /stage/usr/share/doc/kbd-$package_version/"
    ;;
  psmisc)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-psmisc &&
        ./configure --prefix=/usr &&
        make -j$jobs &&
        make DESTDIR=/stage install"
    ;;
  man-pages)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-man-pages &&
        rm -f man3/crypt* &&
        make -R GIT=false prefix=/usr DESTDIR=/stage install"
    ;;
  iana-etc)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-iana-etc &&
        install -d /stage/etc &&
        install -m 0644 services protocols /stage/etc/"
    ;;
  file)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-file &&
        ./configure --prefix=/usr --disable-static &&
        make -j$jobs &&
        make DESTDIR=/stage install"
    ;;
  tcl)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-tcl &&
        source_dir=\$(pwd) &&
        cd unix &&
        ./configure --prefix=/usr \
          --mandir=/usr/share/man \
          --disable-rpath &&
        make -j$jobs &&
        sed -e \"s|\$source_dir/unix|/usr/lib|\" \
          -e \"s|\$source_dir|/usr/include|\" \
          -i tclConfig.sh &&
        sed -e \"s|\$source_dir/unix/pkgs/tdbc1.1.12|/usr/lib/tdbc1.1.12|\" \
          -e \"s|\$source_dir/pkgs/tdbc1.1.12/generic|/usr/include|\" \
          -e \"s|\$source_dir/pkgs/tdbc1.1.12/library|/usr/lib/tcl8.6|\" \
          -e \"s|\$source_dir/pkgs/tdbc1.1.12|/usr/include|\" \
          -i pkgs/tdbc1.1.12/tdbcConfig.sh &&
        sed -e \"s|\$source_dir/unix/pkgs/itcl4.3.4|/usr/lib/itcl4.3.4|\" \
          -e \"s|\$source_dir/pkgs/itcl4.3.4/generic|/usr/include|\" \
          -e \"s|\$source_dir/pkgs/itcl4.3.4|/usr/include|\" \
          -i pkgs/itcl4.3.4/itclConfig.sh &&
        make DESTDIR=/stage install &&
        chmod 0644 /stage/usr/lib/libtclstub8.6.a &&
        chmod u+w /stage/usr/lib/libtcl8.6.so &&
        make DESTDIR=/stage install-private-headers &&
        ln -sfn tclsh8.6 /stage/usr/bin/tclsh &&
        mv /stage/usr/share/man/man3/Thread.3 \
          /stage/usr/share/man/man3/Tcl_Thread.3 &&
        cd .. &&
        tar -xf ../tcl8.6.17-html.tar.gz --strip-components=1 &&
        install -d /stage/usr/share/doc/tcl-$package_version &&
        cp -a html/. /stage/usr/share/doc/tcl-$package_version/"
    ;;
  expect)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-expect &&
        patch -Np1 -i ../expect-5.45.4-gcc15-1.patch &&
        ./configure --prefix=/usr \
          --with-tcl=/usr/lib \
          --enable-shared \
          --disable-rpath \
          --mandir=/usr/share/man \
          --with-tclinclude=/usr/include &&
        make -j$jobs &&
        make DESTDIR=/stage install &&
        ln -sfn expect5.45.4/libexpect5.45.4.so \
          /stage/usr/lib/libexpect5.45.4.so"
    ;;
  dejagnu)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-dejagnu &&
        mkdir -p build &&
        cd build &&
        ../configure --prefix=/usr &&
        makeinfo --html --no-split -o doc/dejagnu.html \
          ../doc/dejagnu.texi &&
        makeinfo --plaintext -o doc/dejagnu.txt \
          ../doc/dejagnu.texi &&
        make DESTDIR=/stage install &&
        install -d /stage/usr/share/doc/dejagnu-$package_version &&
        install -m 0644 doc/dejagnu.html doc/dejagnu.txt \
          /stage/usr/share/doc/dejagnu-$package_version/"
    ;;
  sed)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-sed &&
        ./configure --prefix=/usr &&
        make -j$jobs &&
        make -j$jobs html &&
        make DESTDIR=/stage install &&
        install -d -m 0755 /stage/usr/share/doc/sed-$package_version &&
        install -m 0644 doc/sed.html \
          /stage/usr/share/doc/sed-$package_version/"
    ;;
  gettext)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-gettext &&
        ./configure --prefix=/usr \
          --disable-static \
          --docdir=/usr/share/doc/gettext-$package_version &&
        make -j$jobs &&
        make DESTDIR=/stage install &&
        chmod 0755 /stage/usr/lib/preloadable_libintl.so"
    ;;
  grep)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-grep &&
        sed -i 's/echo/#echo/' src/egrep.sh &&
        ./configure --prefix=/usr &&
        make -j$jobs &&
        make DESTDIR=/stage install"
    ;;
  bash)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-bash &&
        ./configure --prefix=/usr \
          --without-bash-malloc \
          --with-installed-readline \
          --docdir=/usr/share/doc/bash-$package_version &&
        make -j$jobs &&
        make DESTDIR=/stage install"
    ;;
  perl)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      BUILD_ZLIB=False BUILD_BZIP2=0 \
      bash -lc "cd /sources/xbpkg-perl &&
        sh Configure -des \
          -D prefix=/usr \
          -D vendorprefix=/usr \
          -D privlib=/usr/lib/perl5/5.42/core_perl \
          -D archlib=/usr/lib/perl5/5.42/core_perl \
          -D sitelib=/usr/lib/perl5/5.42/site_perl \
          -D sitearch=/usr/lib/perl5/5.42/site_perl \
          -D vendorlib=/usr/lib/perl5/5.42/vendor_perl \
          -D vendorarch=/usr/lib/perl5/5.42/vendor_perl \
          -D man1dir=/usr/share/man/man1 \
          -D man3dir=/usr/share/man/man3 \
          -D pager='/usr/bin/less -isR' \
          -D useshrplib \
          -D usethreads &&
        make -j$jobs &&
        make DESTDIR=/stage install"
    ;;
  xml-parser)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-xml-parser &&
        perl Makefile.PL &&
        make -j$jobs &&
        make DESTDIR=/stage install"
    ;;
  intltool)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-intltool &&
        python3 -c 'p=\"intltool-update.in\"; b=chr(92); d=chr(36); \
s=open(p).read(); open(p,\"w\").write(s.replace(b+d+\"{\",b+d+b+\"{\"))' &&
        ./configure --prefix=/usr &&
        make -j$jobs &&
        make DESTDIR=/stage install &&
        install -Dm 0644 doc/I18N-HOWTO \
          /stage/usr/share/doc/intltool-$package_version/I18N-HOWTO"
    ;;
  wheel)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-wheel &&
        python3 -m pip wheel -w dist \
          --no-cache-dir --no-build-isolation --no-deps . &&
        python3 -m pip install --root=/stage --prefix=/usr \
          --ignore-installed --no-deps --no-index --find-links dist wheel"
    ;;
  setuptools)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-setuptools &&
        python3 -m pip wheel -w dist \
          --no-cache-dir --no-build-isolation --no-deps . &&
        python3 -m pip install --root=/stage --prefix=/usr \
          --ignore-installed --no-deps --no-index --find-links dist setuptools"
    ;;
  coreutils)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      FORCE_UNSAFE_CONFIGURE=1 \
      bash -lc "cd /sources/xbpkg-coreutils &&
        patch -Np1 -i ../coreutils-9.10-i18n-1.patch &&
        autoreconf -fv &&
        automake -af &&
        ./configure --prefix=/usr &&
        make -j$jobs &&
        make DESTDIR=/stage install &&
        install -d /stage/usr/sbin /stage/usr/share/man/man8 &&
        mv /stage/usr/bin/chroot /stage/usr/sbin/ &&
        mv /stage/usr/share/man/man1/chroot.1 \
          /stage/usr/share/man/man8/chroot.8 &&
        sed -i 's/\"1\"/\"8\"/' /stage/usr/share/man/man8/chroot.8"
    ;;
  diffutils)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-diffutils &&
        ./configure --prefix=/usr &&
        make -j$jobs &&
        make DESTDIR=/stage install"
    ;;
  gawk)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-gawk &&
        sed -i 's/extras//' Makefile.in &&
        ./configure --prefix=/usr &&
        make -j$jobs &&
        make DESTDIR=/stage install &&
        ln -sfn gawk.1 /stage/usr/share/man/man1/awk.1 &&
        install -d /stage/usr/share/doc/gawk-$package_version &&
        install -m 0644 doc/awkforai.txt doc/*.eps doc/*.pdf doc/*.jpg \
          /stage/usr/share/doc/gawk-$package_version/"
    ;;
  findutils)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-findutils &&
        ./configure --prefix=/usr --localstatedir=/var/lib/locate &&
        make -j$jobs &&
        make DESTDIR=/stage install"
    ;;
  groff)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-groff &&
        PAGE=A4 ./configure --prefix=/usr &&
        make -j$jobs &&
        make DESTDIR=/stage install"
    ;;
  gzip)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-gzip &&
        ./configure --prefix=/usr &&
        make -j$jobs &&
        make DESTDIR=/stage install"
    ;;
  make)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-make &&
        ./configure --prefix=/usr &&
        make -j$jobs &&
        make DESTDIR=/stage install"
    ;;
  patch)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-patch &&
        ./configure --prefix=/usr &&
        make -j$jobs &&
        make DESTDIR=/stage install"
    ;;
  tar)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      FORCE_UNSAFE_CONFIGURE=1 \
      bash -lc "cd /sources/xbpkg-tar &&
        ./configure --prefix=/usr &&
        make -j$jobs &&
        make DESTDIR=/stage install &&
        make -C doc DESTDIR=/stage install-html \
          docdir=/usr/share/doc/tar-$package_version"
    ;;
  texinfo)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-texinfo &&
        sed 's/! \$output_file eq/\$output_file ne/' \
          -i tp/Texinfo/Convert/*.pm &&
        ./configure --prefix=/usr &&
        make -j$jobs &&
        make DESTDIR=/stage install &&
        make DESTDIR=/stage TEXMF=/usr/share/texmf install-tex"
    ;;
  vim)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-vim &&
        printf '%s\n' \
          '#define SYS_VIMRC_FILE \"/etc/vimrc\"' >>src/feature.h &&
        ./configure --prefix=/usr &&
        make -j$jobs &&
        make DESTDIR=/stage install &&
        ln -sfn vim /stage/usr/bin/vi &&
        find /stage/usr/share/man -path '*/man1/vim.1' | \
          while read -r page; do
            ln -sfn vim.1 \"\$(dirname \"\$page\")/vi.1\"
          done &&
        install -d /stage/usr/share/doc &&
        ln -sfn ../vim/vim92/doc \
          /stage/usr/share/doc/vim-$package_version &&
        install -d /stage/etc &&
        printf '%s\n' \
          '\" Begin /etc/vimrc' \
          '' \
          'source \$VIMRUNTIME/defaults.vim' \
          'let skip_defaults_vim=1' \
          '' \
          'set nocompatible' \
          'set backspace=2' \
          'set mouse=' \
          'syntax on' \
          'if (&term == \"xterm\") || (&term == \"putty\")' \
          '  set background=dark' \
          'endif' \
          '' \
          '\" End /etc/vimrc' > /stage/etc/vimrc"
    ;;
  dbus)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-dbus &&
        mkdir -p build &&
        cd build &&
        meson setup --prefix=/usr \
          --buildtype=release \
          -D systemd=disabled \
          --wrap-mode=nofallback .. &&
        ninja -j$jobs &&
        DESTDIR=/stage ninja install &&
        install -d /stage/var/lib/dbus &&
        ln -sfn /etc/machine-id /stage/var/lib/dbus/machine-id"
    ;;
  util-linux)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-util-linux &&
        ./configure \
          --bindir=/usr/bin \
          --libdir=/usr/lib \
          --runstatedir=/run \
          --sbindir=/usr/sbin \
          --disable-chfn-chsh \
          --disable-login \
          --disable-nologin \
          --disable-su \
          --disable-setpriv \
          --disable-runuser \
          --disable-pylibmount \
          --disable-liblastlog2 \
          --disable-static \
          --without-python \
          --without-systemd \
          --without-udev \
          ADJTIME_PATH=/var/lib/hwclock/adjtime \
          --docdir=/usr/share/doc/util-linux-$package_version &&
        make -j$jobs &&
        make DESTDIR=/stage install"
    ;;
  systemd)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-systemd &&
        sed -e 's/GROUP=\"render\"/GROUP=\"video\"/' \
          -e 's/GROUP=\"sgx\", //' \
          -i rules.d/50-udev-default.rules.in &&
        mkdir -p build &&
        cd build &&
        meson setup .. \
          --prefix=/usr \
          --buildtype=release \
          -D default-dnssec=no \
          -D firstboot=false \
          -D install-tests=false \
          -D ldconfig=false \
          -D sysusers=false \
          -D rpmmacrosdir=no \
          -D homed=disabled \
          -D man=disabled \
          -D mode=release \
          -D pamconfdir=no \
          -D dev-kvm-mode=0660 \
          -D nobody-group=nogroup \
          -D sysupdate=disabled \
          -D ukify=disabled \
          -D docdir=/usr/share/doc/systemd-$package_version &&
        ninja -j$jobs &&
        DESTDIR=/stage ninja install &&
        install -d /stage/usr/share/man &&
        tar -xf ../../systemd-man-pages-259.1.tar.xz \
          --no-same-owner --strip-components=1 \
          -C /stage/usr/share/man"
    ;;
  grub)
    chroot "$rootfs" /usr/bin/env -i \
      HOME=/root TERM="${TERM:-dumb}" PATH=/usr/bin:/usr/sbin \
      bash -lc "cd /sources/xbpkg-grub &&
        sed 's/--image-base/--nonexist-linker-option/' -i configure &&
        ./configure --prefix=/usr \
          --sysconfdir=/etc \
          --disable-efiemu \
          --disable-werror &&
        make -j$jobs &&
        make DESTDIR=/stage install"
    ;;
  *)
    echo "unsupported prototype package: $package_name" >&2
    exit 2
    ;;
esac
fi

if [[ -z "$(find "$stage" -mindepth 1 -print -quit)" ]]; then
  echo "package payload is empty: $package_name" >&2
  exit 1
fi

# install-info maintains this host-wide index. Packaging it would make every
# package that ships Info manuals collide with the first one installed.
rm -f "$stage/usr/share/info/dir"

mkdir -p "$metadata/.XBPKG" "$metadata/rootfs"
if [[ -d "$stage/.xbpkg-hooks" ]]; then
  find "$stage/.xbpkg-hooks" -mindepth 1 -maxdepth 1 -type f \
    ! -name post-install ! -name pre-remove ! -name paths -print -quit |
    grep -q . && {
      echo "unsupported package hook for $package_name" >&2
      exit 1
    }
  install -d -m 0755 "$metadata/.XBPKG/hooks"
  for hook in post-install pre-remove; do
    [[ ! -f "$stage/.xbpkg-hooks/$hook" ]] ||
      install -m 0755 "$stage/.xbpkg-hooks/$hook" \
        "$metadata/.XBPKG/hooks/$hook"
  done
  [[ ! -f "$stage/.xbpkg-hooks/paths" ]] || {
    install -m 0644 "$stage/.xbpkg-hooks/paths" \
      "$metadata/.XBPKG/hook-paths"
    rm -f "$metadata/.XBPKG/hooks/paths"
  }
  rm -rf "$stage/.xbpkg-hooks"
fi
cp -a "$stage/." "$metadata/rootfs/"
(
  cd "$metadata/rootfs"
  find . \( -type f -o -type l \) -printf '/%P\n' | LC_ALL=C sort \
    >../.XBPKG/files
  find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum \
    >../.XBPKG/files.sha256
  if [[ -d etc ]]; then
    find etc -type f -printf '/%p\n' | LC_ALL=C sort \
      >../.XBPKG/conffiles
  else
    : >../.XBPKG/conffiles
  fi
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
conffiles: .XBPKG/conffiles
EOF
if [[ -d "$metadata/.XBPKG/hooks" ]]; then
  printf '%s\n' 'hooks: .XBPKG/hooks' >>"$metadata/.XBPKG/manifest.yaml"
  printf '%s\n' 'hook-paths: .XBPKG/hook-paths' \
    >>"$metadata/.XBPKG/manifest.yaml"
fi
if [[ "$package_name" == glibc ]]; then
  printf '%s\n' 'essential: true' >>"$metadata/.XBPKG/manifest.yaml"
fi

package_archive="$output_dir/$package_name-$package_version-x86_64.xbpkg.tar.zst"
tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner \
  --zstd -C "$metadata" -cf "$package_archive" .XBPKG rootfs
(
  cd "$output_dir"
  sha256sum "$(basename "$package_archive")" \
    >"$(basename "$package_archive").sha256"
)
