#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: download-provisioning-sources.sh OUTPUT_DIR" >&2
  exit 2
fi

output_dir=$1
mkdir -p "$output_dir"

download() {
  local checksum=$1
  local name=$2
  local url=$3
  local target="$output_dir/$name"

  if [[ ! -f "$target" ]] || ! printf '%s  %s\n' "$checksum" "$target" | sha256sum --check --status; then
    rm -f "$target"
    curl --fail --location --retry 3 --output "$target" "$url"
  fi
  printf '%s  %s\n' "$checksum" "$target" | sha256sum --check
}

download \
  4a38a1ab3adb1199257edc2a7c4a2bd714665eb605b04368843b06dada2cfcfb \
  sudo-1.9.17p2.tar.gz \
  https://www.sudo.ws/dist/sudo-1.9.17p2.tar.gz
download \
  ef6026dd2aea8d56059638d5d3262902c892ceba9f88395835e0d06d3fb63238 \
  openssh-10.4p1.tar.gz \
  https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/openssh-10.4p1.tar.gz

cat >"$output_dir/SHA256SUMS" <<'EOF'
4a38a1ab3adb1199257edc2a7c4a2bd714665eb605b04368843b06dada2cfcfb  sudo-1.9.17p2.tar.gz
ef6026dd2aea8d56059638d5d3262902c892ceba9f88395835e0d06d3fb63238  openssh-10.4p1.tar.gz
EOF
(cd "$output_dir" && sha256sum --check SHA256SUMS)
