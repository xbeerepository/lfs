#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "usage: download-icon-sources.sh BASE_SOURCES MANIFEST RETRIES OUT" >&2
  exit 2
fi

base_sources=$1
manifest=$2
retries=$3
output_root=$4
output_dir="$output_root/opt/xbee-lfs-native/sources"

for required in "$base_sources/MD5SUMS" "$base_sources/sources.tsv" "$manifest"; do
  [[ -f "$required" ]] || {
    echo "required source artefact not found: $required" >&2
    exit 1
  }
done

(cd "$base_sources" && md5sum --check MD5SUMS)
install -d "$output_dir"
cp -a "$base_sources/." "$output_dir/"

while IFS=$'\t' read -r checksum filename url; do
  [[ -z "$checksum" || "${checksum:0:1}" == "#" ]] && continue
  target="$output_dir/$filename"
  wget --tries="$retries" --timeout=30 --output-document="$target.part" "$url"
  printf '%s  %s\n' "$checksum" "$target.part" | md5sum --check --status
  mv "$target.part" "$target"
  printf '%s\t%s\t%s\n' "$checksum" "$filename" "$url" \
    >>"$output_dir/sources.tsv"
done <"$manifest"

(
  cd "$output_dir"
  awk -F '\t' '!/^#/ && NF == 3 { values[$2] = $1 }
    END { for (file in values) print values[file] "  " file }' \
    sources.tsv | LC_ALL=C sort -k2 >MD5SUMS
  md5sum --check MD5SUMS
  find . -maxdepth 1 -type f -printf '%f\n' | LC_ALL=C sort >FILES
)
