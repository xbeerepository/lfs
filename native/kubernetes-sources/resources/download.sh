#!/usr/bin/env bash
set -euo pipefail

manifest=$1
output_root=$2
output="$output_root/opt/xbee-kubernetes/sources"
cache=${XBEE_KUBERNETES_DOWNLOAD_CACHE:-/xbee/.xbee/download-cache/kubernetes}
mkdir -p "$output" "$cache"

while read -r checksum filename url; do
  [[ -n "$checksum" && "${checksum:0:1}" != "#" ]] || continue
  target="$output/$filename"
  cached="$cache/$filename"
  if [[ -f "$cached" ]] && printf '%s  %s\n' "$checksum" "$cached" | sha256sum -c --status; then
    cp "$cached" "$target"
  else
    curl --fail --location --retry 3 --output "$target.part" "$url"
    printf '%s  %s\n' "$checksum" "$target.part" | sha256sum -c --status
    mv "$target.part" "$target"
    cp "$target" "$cached"
  fi
done <"$manifest"
cp "$manifest" "$output/SHA256SUMS.tsv"
