#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 6 ]]; then
  echo "usage: build-chroot-system.sh SOURCES TEMPORARY_ARCHIVE JOBS HOSTNAME SRC OUT" >&2
  exit 2
fi

source_dir=$1
temporary_archive=$2
jobs=$3
lfs_hostname=$4
source_root=$5
output_root=$6

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
if [[ ! "$lfs_hostname" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*$ ]]; then
  echo "lfs.hostname is not a valid hostname: $lfs_hostname" >&2
  exit 2
fi
if [[ ! -f "$source_dir/MD5SUMS" ]]; then
  echo "verified source artefact not found at $source_dir" >&2
  exit 1
fi
if [[ ! -f "$temporary_archive" ]]; then
  echo "temporary-system artefact not found: $temporary_archive" >&2
  exit 1
fi
if [[ ! -f "$temporary_archive.sha256" ]]; then
  echo "temporary-system checksum not found: $temporary_archive.sha256" >&2
  exit 1
fi

(cd "$source_dir" && md5sum --check MD5SUMS)
expected_checksum=$(awk 'NR == 1 {print $1}' "$temporary_archive.sha256")
actual_checksum=$(sha256sum "$temporary_archive" | awk '{print $1}')
if [[ -z "$expected_checksum" || "$actual_checksum" != "$expected_checksum" ]]; then
  echo "temporary-system checksum mismatch: $temporary_archive" >&2
  exit 1
fi

work_root="$source_root/native-chroot"
lfs_root="$work_root/rootfs"
output_dir="$output_root/opt/xbee-lfs-native"

rm -rf "$work_root"
mkdir -p "$lfs_root" "$output_dir"
tar --zstd --xattrs --acls --numeric-owner -xf "$temporary_archive" -C "$lfs_root"
mkdir -p "$lfs_root/sources"
cp -a "$source_dir/." "$lfs_root/sources/"
chmod 1777 "$lfs_root/sources"
chown -R root:root "$lfs_root"

mkdir -pv "$lfs_root"/{boot,home,mnt,opt,srv}
mkdir -pv "$lfs_root"/etc/{opt,sysconfig}
mkdir -pv "$lfs_root"/lib/firmware
mkdir -pv "$lfs_root"/media/{floppy,cdrom}
mkdir -pv "$lfs_root"/usr/{,local/}{include,src}
mkdir -pv "$lfs_root"/usr/lib/locale
mkdir -pv "$lfs_root"/usr/local/{bin,lib,sbin}
mkdir -pv "$lfs_root"/usr/{,local/}share/{color,dict,doc,info,locale,man}
mkdir -pv "$lfs_root"/usr/{,local/}share/{misc,terminfo,zoneinfo}
mkdir -pv "$lfs_root"/usr/{,local/}share/man/man{1..8}
mkdir -pv "$lfs_root"/var/{cache,local,log,mail,opt,spool}
mkdir -pv "$lfs_root"/var/lib/{color,misc,locate}
mkdir -pv "$lfs_root"/run/lock
mkdir -pv "$lfs_root"/{dev/pts,dev/shm,proc,sys}
chmod 1777 "$lfs_root/dev/shm"

mknod -m 0666 "$lfs_root/dev/null" c 1 3
mknod -m 0666 "$lfs_root/dev/zero" c 1 5
mknod -m 0666 "$lfs_root/dev/random" c 1 8
mknod -m 0666 "$lfs_root/dev/urandom" c 1 9
mknod -m 0666 "$lfs_root/dev/tty" c 5 0
ln -sfn /proc/self/fd "$lfs_root/dev/fd"
ln -sfn /proc/self/fd/0 "$lfs_root/dev/stdin"
ln -sfn /proc/self/fd/1 "$lfs_root/dev/stdout"
ln -sfn /proc/self/fd/2 "$lfs_root/dev/stderr"

ln -sfn /run "$lfs_root/var/run"
ln -sfn /run/lock "$lfs_root/var/lock"
ln -sfn /proc/self/mounts "$lfs_root/etc/mtab"

install -dv -m 0750 "$lfs_root/root"
install -dv -m 1777 "$lfs_root/tmp" "$lfs_root/var/tmp"

cat >"$lfs_root/etc/hosts" <<EOF
127.0.0.1  localhost $lfs_hostname
::1        localhost
EOF

cat >"$lfs_root/etc/passwd" <<'EOF'
root:x:0:0:root:/root:/bin/bash
bin:x:1:1:bin:/dev/null:/usr/bin/false
daemon:x:6:6:Daemon User:/dev/null:/usr/bin/false
messagebus:x:18:18:D-Bus Message Daemon User:/run/dbus:/usr/bin/false
systemd-journal-gateway:x:73:73:systemd Journal Gateway:/:/usr/bin/false
systemd-journal-remote:x:74:74:systemd Journal Remote:/:/usr/bin/false
systemd-journal-upload:x:75:75:systemd Journal Upload:/:/usr/bin/false
systemd-network:x:76:76:systemd Network Management:/:/usr/bin/false
systemd-resolve:x:77:77:Systemd Resolver:/:/usr/bin/false
systemd-timesync:x:78:78:Systemd Time Synchronization:/:/usr/bin/false
systemd-coredump:x:79:79:Systemd Core Dumper:/:/usr/bin/false
uuidd:x:80:80:UUID Generation Daemon User:/dev/null:/usr/bin/false
systemd-oom:x:81:81:Systemd Out Of Memory Daemon:/:/usr/bin/false
nobody:x:65534:65534:Unprivileged User:/dev/null:/usr/bin/false
tester:x:101:101::/home/tester:/bin/bash
EOF

cat >"$lfs_root/etc/group" <<'EOF'
root:x:0:
bin:x:1:daemon
sys:x:2:
kmem:x:3:
tape:x:4:
tty:x:5:
daemon:x:6:
floppy:x:7:
disk:x:8:
lp:x:9:
dialout:x:10:
audio:x:11:
video:x:12:
utmp:x:13:
clock:x:14:
cdrom:x:15:
adm:x:16:
messagebus:x:18:
systemd-journal:x:23:
input:x:24:
mail:x:34:
kvm:x:61:
systemd-journal-gateway:x:73:
systemd-journal-remote:x:74:
systemd-journal-upload:x:75:
systemd-network:x:76:
systemd-resolve:x:77:
systemd-timesync:x:78:
systemd-coredump:x:79:
uuidd:x:80:
systemd-oom:x:81:
wheel:x:97:
tester:x:101:
users:x:999:
nogroup:x:65534:
EOF

install -o 101 -g 101 -d "$lfs_root/home/tester"
touch "$lfs_root"/var/log/{btmp,lastlog,faillog,wtmp}
chgrp 13 "$lfs_root/var/log/lastlog"
chmod 0664 "$lfs_root/var/log/lastlog"
chmod 0600 "$lfs_root/var/log/btmp"

worker_script="$lfs_root/tmp/chapter7-worker.sh"
{
  printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail'
  sed -n '/^extract_source()/,$p' "$0"
} >"$worker_script"
chmod 0755 "$worker_script"

chroot "$lfs_root" /usr/bin/env -i \
  HOME=/root \
  TERM="${TERM:-dumb}" \
  PS1='(lfs chroot) \u:\w\$ ' \
  PATH=/usr/bin:/usr/sbin \
  MAKEFLAGS="-j$jobs" \
  TESTSUITEFLAGS="-j$jobs" \
  /bin/bash --noprofile --norc /tmp/chapter7-worker.sh

rm -f "$worker_script"
rm -rf "$lfs_root/sources/work"

for command in bash bison gcc msgfmt perl python3 texi2any; do
  if [[ ! -x "$lfs_root/usr/bin/$command" ]]; then
    echo "chapter 7 command was not produced: /usr/bin/$command" >&2
    exit 1
  fi
done

chroot "$lfs_root" /usr/bin/env -i \
  HOME=/root \
  PATH=/usr/bin:/usr/sbin \
  /bin/bash --noprofile --norc -c '
    gcc --version >/dev/null
    bash --version >/dev/null
    python3 --version
    getconf GNU_LIBC_VERSION
  '

archive="$output_dir/chroot-rootfs.tar.zst"
tar --xattrs --acls --numeric-owner --zstd \
  --exclude='./sources' \
  -C "$lfs_root" -cf "$archive" .
(
  cd "$output_dir"
  sha256sum "$(basename "$archive")" >"$(basename "$archive").sha256"
)

cat >"$output_dir/chroot-metadata.yaml" <<EOF
schema-version: 1
lfs-book: "13.0"
stage: chroot-system
architecture: x86_64
jobs: $jobs
hostname: "$lfs_hostname"
packages:
  gettext: "1.0"
  bison: "3.8.2"
  perl: "5.42.0"
  python: "3.14.3"
  texinfo: "7.2"
  util-linux: "2.41.3"
artefacts:
  rootfs: chroot-rootfs.tar.zst
  checksum: chroot-rootfs.tar.zst.sha256
EOF
exit 0

# Everything below this point runs as root inside the LFS chroot.
extract_source() {
  local archive=$1
  local top
  top=$(tar -tf "/sources/$archive" | sed -n '1{s@^\./@@;s@/.*@@;p;q}')
  if [[ -z "$top" ]]; then
    echo "cannot determine source directory for $archive" >&2
    exit 1
  fi
  rm -rf "/sources/work/$top"
  tar -xf "/sources/$archive" -C /sources/work
  printf '%s\n' "/sources/work/$top"
}

announce() {
  printf '\n===== LFS native chroot: %s =====\n' "$1"
}

mkdir -p /sources/work

announce "Gettext 1.0"
package_dir=$(extract_source gettext-1.0.tar.xz)
(
  cd "$package_dir"
  ./configure --disable-shared
  make
  cp -v gettext-tools/src/{msgfmt,msgmerge,xgettext} /usr/bin
)

announce "Bison 3.8.2"
package_dir=$(extract_source bison-3.8.2.tar.xz)
(
  cd "$package_dir"
  ./configure \
    --prefix=/usr \
    --docdir=/usr/share/doc/bison-3.8.2
  make
  make install
)

announce "Perl 5.42.0"
package_dir=$(extract_source perl-5.42.0.tar.xz)
(
  cd "$package_dir"
  sh Configure -des \
    -D prefix=/usr \
    -D vendorprefix=/usr \
    -D useshrplib \
    -D privlib=/usr/lib/perl5/5.42/core_perl \
    -D archlib=/usr/lib/perl5/5.42/core_perl \
    -D sitelib=/usr/lib/perl5/5.42/site_perl \
    -D sitearch=/usr/lib/perl5/5.42/site_perl \
    -D vendorlib=/usr/lib/perl5/5.42/vendor_perl \
    -D vendorarch=/usr/lib/perl5/5.42/vendor_perl
  make
  make install
)

announce "Python 3.14.3"
package_dir=$(extract_source Python-3.14.3.tar.xz)
(
  cd "$package_dir"
  ./configure \
    --prefix=/usr \
    --enable-shared \
    --without-ensurepip \
    --without-static-libpython
  make
  make install
)

announce "Texinfo 7.2"
package_dir=$(extract_source texinfo-7.2.tar.xz)
(
  cd "$package_dir"
  ./configure --prefix=/usr
  make
  make install
)

announce "Util-linux 2.41.3"
package_dir=$(extract_source util-linux-2.41.3.tar.xz)
(
  cd "$package_dir"
  mkdir -pv /var/lib/hwclock
  ./configure \
    --libdir=/usr/lib \
    --runstatedir=/run \
    --disable-chfn-chsh \
    --disable-login \
    --disable-nologin \
    --disable-su \
    --disable-setpriv \
    --disable-runuser \
    --disable-pylibmount \
    --disable-static \
    --disable-liblastlog2 \
    --without-python \
    ADJTIME_PATH=/var/lib/hwclock/adjtime \
    --docdir=/usr/share/doc/util-linux-2.41.3
  make
  make install
)

announce "Chapter 7 cleanup"
rm -rf /usr/share/{info,man,doc}/*
find /usr/{lib,libexec} -name '*.la' -delete
rm -rf /tools

printf '\n===== LFS native: Chapter 7 complete =====\n'
