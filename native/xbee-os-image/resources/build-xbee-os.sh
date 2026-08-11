#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 6 ]]; then
  echo "usage: build-xbee-os.sh REPOSITORY PROFILE IMAGE TAG SRC OUT" >&2
  exit 2
fi

repository=$1
profile_file=$2
image_name=$3
image_tag=$4
source_root=$5
output_root=$6

[[ "$image_name" =~ ^[a-z0-9][a-z0-9._/-]*$ &&
   "$image_tag" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ ]] || {
  echo "invalid Docker image name or tag" >&2
  exit 2
}
[[ -f "$profile_file" ]] || {
  echo "package profile not found: $profile_file" >&2
  exit 1
}

manager="$repository/bin/xbpkg"
repository_key="$repository/repository-ed25519-public.pem"
for required in "$manager" "$repository/SHA256SUMS" \
  "$repository/SHA256SUMS.sig" "$repository/SHA256SUMS.keyid" \
  "$repository_key"; do
  [[ -f "$required" ]] || {
    echo "package repository is incomplete: $required" >&2
    exit 1
  }
done
[[ -x "$manager" && -d "$repository/packages" ]]

repository_key_id=$(head -n 1 "$repository/SHA256SUMS.keyid")
actual_key_id=$(openssl pkey -pubin -in "$repository_key" -outform DER |
  sha256sum | awk '{print $1}')
[[ "$repository_key_id" =~ ^[[:xdigit:]]{64}$ &&
   "$repository_key_id" == "$actual_key_id" ]] || {
  echo "repository signing key identifier mismatch" >&2
  exit 1
}
openssl pkeyutl -verify -pubin -inkey "$repository_key" \
  -sigfile "$repository/SHA256SUMS.sig" -rawin \
  -in "$repository/SHA256SUMS" >/dev/null
(cd "$repository" && sha256sum --quiet -c SHA256SUMS)

work_root="$source_root/xbee-os-build"
rootfs="$work_root/rootfs"
docker_root="$work_root/docker-archive"
output_dir="$output_root/opt/xbee-os"
rm -rf "$work_root"
mkdir -p "$rootfs" "$docker_root" "$output_dir"

while IFS= read -r package; do
  package=${package%%#*}
  package=${package//[[:space:]]/}
  [[ -n "$package" ]] || continue
  [[ "$package" =~ ^[a-z0-9][a-z0-9+._-]*$ ]] || {
    echo "invalid package in profile: $package" >&2
    exit 1
  }
  "$manager" --root "$rootfs" --repository "$repository" \
    --trusted-key "$repository_key" install "$package"
done <"$profile_file"

install -Dm0755 "$manager" "$rootfs/usr/bin/xbpkg"
install -Dm0644 "$repository_key" \
  "$rootfs/etc/xbpkg/trusted-repository-key.pem"
install -Dm0644 "$repository_key" \
  "$rootfs/etc/xbpkg/trusted-keys/$repository_key_id.pem"
: >"$rootfs/etc/xbpkg/revoked-keys"

mkdir -p "$rootfs/dev" "$rootfs/proc" "$rootfs/sys" "$rootfs/run" \
  "$rootfs/tmp" "$rootfs/root" "$rootfs/var/cache/xbpkg/repositories"
chmod 1777 "$rootfs/tmp"
chmod 0700 "$rootfs/root"

for legacy_dir in bin sbin lib lib64; do
  if [[ -d "$rootfs/$legacy_dir" && ! -L "$rootfs/$legacy_dir" ]]; then
    rmdir "$rootfs/$legacy_dir" 2>/dev/null || true
  fi
done
[[ -e "$rootfs/bin" || -L "$rootfs/bin" ]] || ln -s usr/bin "$rootfs/bin"
[[ -e "$rootfs/sbin" || -L "$rootfs/sbin" ]] || ln -s usr/sbin "$rootfs/sbin"
[[ -e "$rootfs/lib" || -L "$rootfs/lib" ]] || ln -s usr/lib "$rootfs/lib"
[[ -e "$rootfs/lib64" || -L "$rootfs/lib64" ]] || ln -s usr/lib64 "$rootfs/lib64"
ln -sfn bash "$rootfs/usr/bin/sh"

cat >"$rootfs/etc/passwd" <<'EOF'
root:x:0:0:root:/root:/bin/bash
nobody:x:65534:65534:Unprivileged User:/dev/null:/bin/false
EOF
cat >"$rootfs/etc/group" <<'EOF'
root:x:0:
nobody:x:65534:
EOF
cat >"$rootfs/etc/nsswitch.conf" <<'EOF'
passwd: files
group: files
shadow: files
hosts: files dns
networks: files
EOF
cat >"$rootfs/etc/os-release" <<'EOF'
NAME="XBee OS"
ID=xbee-os
VERSION="13.0"
VERSION_ID="13.0"
PRETTY_NAME="XBee OS 13.0"
HOME_URL="https://github.com/xbee"
EOF
printf 'xbee-os\n' >"$rootfs/etc/hostname"

packages_file="$output_dir/packages.txt"
"$manager" --root "$rootfs" list | sort >"$packages_file"
package_count=$(wc -l <"$packages_file")
((package_count > 0))
for required in bash coreutils curl openssl tar zstd; do
  awk '{print $1}' "$packages_file" | grep -Fxq "$required" || {
    echo "container profile is missing required package: $required" >&2
    exit 1
  }
done
for excluded in grub linux-kernel linux-modules openssh systemd; do
  if awk '{print $1}' "$packages_file" | grep -Fxq "$excluded"; then
    echo "container profile unexpectedly contains: $excluded" >&2
    exit 1
  fi
done
"$manager" --root "$rootfs" check
chroot "$rootfs" /bin/bash -lc \
  'test "$(. /etc/os-release; printf %s "$ID")" = xbee-os && command -v xbpkg >/dev/null'

epoch=${SOURCE_DATE_EPOCH:-0}
tar_options=(--sort=name --numeric-owner --owner=0 --group=0 \
  --mtime="@$epoch" --format=posix --pax-option=delete=atime,delete=ctime)
rootfs_tar="$output_dir/$image_name-$image_tag-rootfs.tar"
tar "${tar_options[@]}" -C "$rootfs" -cf "$rootfs_tar" .
zstd -T0 -19 -f "$rootfs_tar" -o "$rootfs_tar.zst"

layer_digest=$(sha256sum "$rootfs_tar" | awk '{print $1}')
layer_size=$(stat -c %s "$rootfs_tar")
created=$(date -u -d "@$epoch" '+%Y-%m-%dT%H:%M:%SZ')
config_tmp="$work_root/config.json"
cat >"$config_tmp" <<EOF
{"architecture":"amd64","config":{"Cmd":["/bin/bash"],"Env":["PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"],"Hostname":"","Image":"","Labels":{"org.opencontainers.image.ref.name":"$image_name","org.opencontainers.image.title":"XBee OS","org.opencontainers.image.version":"$image_tag"},"WorkingDir":"/root"},"created":"$created","history":[{"created":"$created","created_by":"xbpkg: XBee OS $image_tag container-minimal"}],"os":"linux","rootfs":{"diff_ids":["sha256:$layer_digest"],"type":"layers"}}
EOF
config_digest=$(sha256sum "$config_tmp" | awk '{print $1}')
install -m 0644 "$config_tmp" "$docker_root/$config_digest.json"
mkdir -p "$docker_root/$layer_digest"
install -m 0644 "$rootfs_tar" "$docker_root/$layer_digest/layer.tar"
printf '1.0\n' >"$docker_root/$layer_digest/VERSION"
cat >"$docker_root/manifest.json" <<EOF
[{"Config":"$config_digest.json","RepoTags":["$image_name:$image_tag","$image_name:latest"],"Layers":["$layer_digest/layer.tar"]}]
EOF
cat >"$docker_root/repositories" <<EOF
{"$image_name":{"$image_tag":"$layer_digest","latest":"$layer_digest"}}
EOF

docker_archive="$output_dir/$image_name-$image_tag-docker.tar"
tar "${tar_options[@]}" -C "$docker_root" -cf "$docker_archive" .
zstd -T0 -19 -f "$docker_archive" -o "$docker_archive.zst"
(
  cd "$output_dir"
  sha256sum "$(basename "$rootfs_tar.zst")" \
    "$(basename "$docker_archive.zst")" >SHA256SUMS
)
rm -f "$rootfs_tar" "$docker_archive"

cat >"$output_dir/metadata.yaml" <<EOF
schema-version: 1
distribution: xbee-os
version: "$image_tag"
base: lfs-13.0
architecture: x86_64
profile: container-minimal
package-count: $package_count
package-manager: xbpkg
image:
  repository: "$image_name"
  tags: ["$image_tag", latest]
  format: docker-archive
  compression: zstd
  file: "$(basename "$docker_archive.zst")"
rootfs: "$(basename "$rootfs_tar.zst")"
EOF
