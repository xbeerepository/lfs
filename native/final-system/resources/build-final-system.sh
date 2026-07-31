#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 8 ]]; then
  echo "usage: build-final-system.sh SOURCES CHROOT_ARCHIVE JOBS TIMEZONE COMMANDS PACKAGES SRC OUT" >&2
  exit 2
fi

source_dir=$1
chroot_archive=$2
jobs=$3
lfs_timezone=$4
commands_dir=$5
packages_file=$6
source_root=$7
output_root=$8

case "$jobs" in
  ''|*[!0-9]*|0)
    echo "lfs.jobs must be a positive integer" >&2
    exit 2
    ;;
esac
if [[ "$(uname -m)" != "x86_64" ]]; then
  echo "the native builder currently supports x86_64 only" >&2
  exit 2
fi
if [[ ! "$lfs_timezone" =~ ^[A-Za-z0-9._+-]+(/[A-Za-z0-9._+-]+)+$ ]]; then
  echo "lfs.timezone is not a valid zoneinfo name: $lfs_timezone" >&2
  exit 2
fi
if [[ ! -f "$source_dir/MD5SUMS" ]]; then
  echo "verified source artefact not found at $source_dir" >&2
  exit 1
fi
if [[ ! -f "$chroot_archive" || ! -f "$chroot_archive.sha256" ]]; then
  echo "chroot-system artefact or checksum not found: $chroot_archive" >&2
  exit 1
fi
if [[ ! -d "$commands_dir" || ! -f "$packages_file" ]]; then
  echo "chapter 8 command resources are incomplete" >&2
  exit 1
fi

(cd "$source_dir" && md5sum --check MD5SUMS)
expected_checksum=$(awk 'NR == 1 {print $1}' "$chroot_archive.sha256")
actual_checksum=$(sha256sum "$chroot_archive" | awk '{print $1}')
if [[ -z "$expected_checksum" || "$actual_checksum" != "$expected_checksum" ]]; then
  echo "chroot-system checksum mismatch: $chroot_archive" >&2
  exit 1
fi

work_root="$source_root/native-final"
lfs_root="$work_root/rootfs"
output_dir="$output_root/opt/xbee-lfs-native"

rm -rf "$work_root"
mkdir -p "$lfs_root" "$output_dir"
tar --zstd --xattrs --acls --numeric-owner -xf "$chroot_archive" -C "$lfs_root"
mkdir -p "$lfs_root/sources" "$lfs_root/tmp/chapter8-commands"
cp -a "$source_dir/." "$lfs_root/sources/"
cp -a "$commands_dir/." "$lfs_root/tmp/chapter8-commands/"
cp "$packages_file" "$lfs_root/tmp/chapter8-packages.tsv"
chmod 1777 "$lfs_root/sources"
chown -R root:root "$lfs_root"

for device in null:1:3 zero:1:5 random:1:8 urandom:1:9 tty:5:0; do
  IFS=: read -r name major minor <<<"$device"
  if [[ ! -e "$lfs_root/dev/$name" ]]; then
    mknod -m 0666 "$lfs_root/dev/$name" c "$major" "$minor"
  fi
done

worker_script="$lfs_root/tmp/chapter8-worker.sh"
{
  printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail'
  sed -n '/^extract_source()/,$p' "$0"
} >"$worker_script"
chmod 0755 "$worker_script"

chroot "$lfs_root" /usr/bin/env -i \
  HOME=/root \
  TERM="${TERM:-dumb}" \
  PATH=/usr/bin:/usr/sbin \
  MAKEFLAGS="-j$jobs" \
  TESTSUITEFLAGS="-j$jobs" \
  LFS_JOBS="$jobs" \
  LFS_TIMEZONE="$lfs_timezone" \
  /bin/bash --noprofile --norc /tmp/chapter8-worker.sh

rm -f "$worker_script"
rm -rf "$lfs_root/sources/work"

for command in bash dbus-daemon gcc ldconfig login make python3 systemctl; do
  command_path=$(chroot "$lfs_root" /usr/bin/env -i PATH=/usr/bin:/usr/sbin \
    /bin/bash --noprofile --norc -c "command -v '$command'")
  if [[ -z "$command_path" ]]; then
    echo "chapter 8 command was not produced: $command" >&2
    exit 1
  fi
done

chroot "$lfs_root" /usr/bin/env -i \
  HOME=/root \
  PATH=/usr/bin:/usr/sbin \
  /bin/bash --noprofile --norc -c '
    gcc --version | head -n1
    getconf GNU_LIBC_VERSION
    python3 --version
    systemctl --version | head -n1
    test "$(readlink /etc/localtime)" = "/usr/share/zoneinfo/'"$lfs_timezone"'"
  '

archive="$output_dir/final-rootfs.tar.zst"
tar --xattrs --acls --numeric-owner --zstd \
  --exclude='./sources' \
  -C "$lfs_root" -cf "$archive" .
(
  cd "$output_dir"
  sha256sum "$(basename "$archive")" >"$(basename "$archive").sha256"
)

cat >"$output_dir/final-metadata.yaml" <<EOF
schema-version: 1
lfs-book: "13.0"
stage: final-system
architecture: x86_64
jobs: $jobs
timezone: "$lfs_timezone"
root-account: locked
tests: omitted
packages: 81
artefacts:
  rootfs: final-rootfs.tar.zst
  checksum: final-rootfs.tar.zst.sha256
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

mkdir -p /sources/work
find /sources -maxdepth 1 -type f -exec ln -sf {} /sources/work/ \;

while IFS=$'\t' read -r command_file archive; do
  [[ -n "$command_file" && -n "$archive" ]] || continue
  printf '\n===== LFS native final: %s =====\n' "$command_file"
  package_dir=$(extract_source "$archive")
  (
    cd "$package_dir"
    # The command files are generated from the LFS 13.0 systemd book.
    # Test-suite commands are intentionally omitted from this builder.
    source "/tmp/chapter8-commands/$command_file"
  )
  rm -rf "$package_dir"
done </tmp/chapter8-packages.tsv

printf '\n===== LFS native final: stripping =====\n'
source /tmp/chapter8-commands/155-stripping

printf '\n===== LFS native final: cleanup =====\n'
source /tmp/chapter8-commands/156-cleanup

printf '\n===== LFS native: Chapter 8 complete =====\n'
