#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "usage: download-final-sources.sh BASE_SOURCES MANIFEST RETRIES OUT" >&2
  exit 2
fi

base_sources=$1
manifest=$2
retries=$3
output_root=$4
output_dir="$output_root/opt/xbee-lfs-native/sources"

case "$retries" in
  ''|*[!0-9]*)
    echo "sources.retries must be a non-negative integer" >&2
    exit 2
    ;;
esac
if [[ ! -f "$base_sources/MD5SUMS" ]]; then
  echo "base source artefact not found: $base_sources" >&2
  exit 1
fi
if [[ ! -f "$manifest" ]]; then
  echo "chapter 8 source manifest not found: $manifest" >&2
  exit 2
fi

(cd "$base_sources" && md5sum --check MD5SUMS)
mkdir -p "$output_dir"
cp -a "$base_sources/." "$output_dir/"
sed '/^#/d' "$manifest" >>"$output_dir/sources.tsv"

download_verified() {
  local checksum=$1
  local target=$2
  local url=$3
  local partial="$target.part"
  local relative candidate candidate_retries
  local -a candidates=("$url")

  if [[ "$url" == https://ftpmirror.gnu.org/* ]]; then
    relative=${url#https://ftpmirror.gnu.org/}
    candidates+=(
      "https://ftp.gnu.org/gnu/$relative"
      "https://mirrors.kernel.org/gnu/$relative"
    )
  elif [[ "$url" == https://download.savannah.gnu.org/* ]]; then
    relative=${url#https://download.savannah.gnu.org/}
    candidates+=("https://download-mirror.savannah.gnu.org/$relative")
  fi

  for candidate in "${candidates[@]}"; do
    candidate_retries=$retries
    if [[ "$candidate" == https://ftpmirror.gnu.org/* ||
      "$candidate" == https://download.savannah.gnu.org/* ]]; then
      candidate_retries=1
    fi
    echo "[final-sources] trying: $candidate"
    if wget \
      --continue \
      --progress=dot:giga \
      --tries="$candidate_retries" \
      --retry-connrefused \
      --retry-on-http-error=500,502,503,504 \
      --waitretry=2 \
      --timeout=30 \
      --output-document="$partial" \
      "$candidate" &&
      printf '%s  %s\n' "$checksum" "$partial" |
        md5sum --check --status; then
      mv "$partial" "$target"
      return 0
    fi
    rm -f "$partial"
    echo "[final-sources] mirror failed: $candidate" >&2
  done

  echo "[final-sources] all mirrors failed: $(basename "$target")" >&2
  return 1
}

while IFS=$'\t' read -r checksum filename url; do
  [[ -z "$checksum" || "${checksum:0:1}" == "#" ]] && continue
  target="$output_dir/$filename"
  if [[ -f "$target" ]] && printf '%s  %s\n' "$checksum" "$target" | md5sum --check --status; then
    echo "[final-sources] cache hit: $filename"
    continue
  fi

  echo "[final-sources] downloading: $filename"
  download_verified "$checksum" "$target" "$url"
done <"$manifest"

(
  cd "$output_dir"
  awk -F '\t' '!/^#/ && NF == 3 { print $1 "  " $2 }' sources.tsv >MD5SUMS
  md5sum --check MD5SUMS
  find . -maxdepth 1 -type f -printf '%f\n' | LC_ALL=C sort >FILES
)

cat >"$output_root/opt/xbee-lfs-native/final-sources-metadata.yaml" <<EOF
schema-version: 1
lfs-book: "13.0"
stages:
  - 5
  - 6
  - 7
  - 8
checksum: md5
manifest: sources/sources.tsv
EOF
