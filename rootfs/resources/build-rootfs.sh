#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 9 ]]; then
  echo "usage: build-rootfs.sh BOOK JOBS TIMEZONE LOCALE HOSTNAME RUN_TESTS SRC OUT" >&2
  exit 2
fi

book_version=$1
jobs=$2
timezone=$3
locale=$4
lfs_hostname=$5
run_tests=$6
source_root=$7
output_root=$8

case "$jobs" in
  ''|*[!0-9]*|0)
    echo "lfs.jobs must be a positive integer, got: $jobs" >&2
    exit 2
    ;;
esac

case "$run_tests" in
  true|false) ;;
  *)
    echo "lfs.run-tests must be true or false, got: $run_tests" >&2
    exit 2
    ;;
esac

build_user=xbee-lfs-build
work_root="$source_root/lfs-$book_version"
jhalfs_root="$work_root/jhalfs-source"
lfs_root="$work_root/rootfs"
source_archive="$work_root/source-archive"
output_dir="$output_root/opt/xbee-lfs"
resource_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

if [[ "$(uname -m)" != "x86_64" ]]; then
  echo "the MVP currently supports x86_64 only" >&2
  exit 2
fi

if ! id "$build_user" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash "$build_user"
fi
cat >"/etc/sudoers.d/$build_user" <<EOF
$build_user ALL=(ALL) NOPASSWD:ALL
EOF
chmod 0440 "/etc/sudoers.d/$build_user"

mkdir -p "$work_root" "$lfs_root/sources" "$source_archive" "$output_dir"
chmod 1777 "$lfs_root/sources"
chown -R "$build_user:$build_user" "$work_root"

if [[ ! -d "$jhalfs_root/.git" ]]; then
  sudo -u "$build_user" git clone --depth 1 \
    https://git.linuxfromscratch.org/jhalfs.git "$jhalfs_root"
fi

kernel_config="$work_root/kernel-x86_64.config"
fstab="$work_root/fstab"
install -o "$build_user" -g "$build_user" -m 0644 \
  "$resource_root/kernel-x86_64.config" "$kernel_config"
install -o "$build_user" -g "$build_user" -m 0644 \
  "$resource_root/fstab" "$fstab"

tests_config=n
tests_level=
if [[ "$run_tests" == "true" ]]; then
  tests_config=y
  tests_level=TST_1
fi

partial_config="$jhalfs_root/xbee.configuration"
cat >"$partial_config" <<EOF
BOOK_LFS_ANY=y
BOOK_LFS_SYSD=y
BRANCH=y
COMMIT="$book_version"
LFS_MULTILIB_NO=y
BUILD_CHROOT=y
LUSER="lfs"
LGROUP="lfs"
BUILDDIR="$lfs_root"
GETPKG=y
SRC_ARCHIVE="$source_archive"
RUNMAKE=n
CLEAN=y
ALL_CORES=n
N_PARALLEL=$jobs
CONFIG_TESTS=$tests_config
$tests_level
KEEPDIR=n
TEST_MISMATCH=y
PKGMNGT=n
INSTALL_LOG=y
STRIP=y
NO_PROGRESS_BAR=y
HAVE_FSTAB=y
FSTAB="$fstab"
CONFIG_BUILD_KERNEL=y
CONFIG="$kernel_config"
TIMEZONE="$timezone"
LANG="$locale"
FULL_LOCALE=n
PAGE_A4=y
HOSTNAME="$lfs_hostname"
INTERFACE="eth0"
IP_ADDR="10.0.2.15"
GATEWAY="10.0.2.2"
PREFIX="24"
BROADCAST="10.0.2.255"
DOMAIN="local"
DNS1="10.0.2.3"
DNS2="1.1.1.1"
FONT="lat0-16"
KEYMAP="us"
LOCAL=n
LOG_LEVEL="4"
REPORT=y
EOF
chown "$build_user:$build_user" "$partial_config"

sudo -u "$build_user" env JHALFS_ROOT="$jhalfs_root" python3 - <<'PY'
import os
import sys

root = os.environ["JHALFS_ROOT"]
os.chdir(root)
os.environ["CONFIG_"] = ""
sys.path.insert(0, os.path.join(root, "menu"))
import kconfiglib

config = kconfiglib.Kconfig("Config.in")
config.load_config("xbee.configuration")
config.write_config("configuration")
PY

sudo -u "$build_user" bash -c \
  "cd '$jhalfs_root' && printf '\\n' | ./jhalfs run"
sudo -u "$build_user" make -C "$lfs_root/jhalfs"

if [[ ! -x "$lfs_root/bin/bash" && ! -x "$lfs_root/usr/bin/bash" ]]; then
  echo "jhalfs completed without producing a usable root filesystem" >&2
  exit 1
fi
if ! compgen -G "$lfs_root/boot/vmlinuz-*" >/dev/null; then
  echo "jhalfs completed without producing a kernel in /boot" >&2
  exit 1
fi

archive="$output_dir/rootfs.tar.zst"
tar --xattrs --acls --numeric-owner --one-file-system \
  --exclude='./sources' \
  --exclude='./jhalfs' \
  --zstd -C "$lfs_root" -cf "$archive" .
sha256sum "$archive" >"$archive.sha256"

jhalfs_commit=$(git -C "$jhalfs_root" rev-parse HEAD)
cat >"$output_dir/build-metadata.yaml" <<EOF
schema-version: 1
distribution:
  name: xbee-lfs
  lfs-book: "$book_version"
  init: systemd
  architecture: x86_64
build:
  jhalfs-commit: "$jhalfs_commit"
  jobs: $jobs
  tests: $run_tests
  timezone: "$timezone"
  locale: "$locale"
  hostname: "$lfs_hostname"
artefacts:
  rootfs: rootfs.tar.zst
  checksum: rootfs.tar.zst.sha256
EOF
