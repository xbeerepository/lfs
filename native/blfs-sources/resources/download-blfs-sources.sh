#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "usage: download-blfs-sources.sh BASE_SOURCES MANIFEST RETRIES OUT" >&2
  exit 2
fi

base_sources=$1
manifest=$2
retries=$3
output_root=$4
output_dir="$output_root/opt/xbee-lfs-native/sources"
download_cache=${XBEE_BLFS_DOWNLOAD_CACHE:-/xbee/.xbee/download-cache/blfs-13.0}

case "$retries" in
  ''|*[!0-9]*)
    echo "sources.retries must be a non-negative integer" >&2
    exit 2
    ;;
esac
for required in "$base_sources/MD5SUMS" "$base_sources/sources.tsv" "$manifest"; do
  [[ -f "$required" ]] || {
    echo "required source artefact not found: $required" >&2
    exit 1
  }
done

(cd "$base_sources" && md5sum --check MD5SUMS)
mkdir -p "$output_dir"
mkdir -p "$download_cache"
cp -a "$base_sources/." "$output_dir/"

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
      "https://mirrors.kernel.org/gnu/$relative"
      "https://ftp.gnu.org/gnu/$relative"
    )
  fi
  if [[ "$url" == https://www.lua.org/ftp/* ]]; then
    candidates+=(
      "https://sources.buildroot.net/lua/$(basename "$url")"
    )
  fi
  if [[ "$url" == https://www.mirbsd.org/* ]]; then
    candidates+=("http://${url#https://}")
  fi

  for candidate in "${candidates[@]}"; do
    candidate_retries=$retries
    if [[ "$candidate" == https://ftpmirror.gnu.org/* ||
          "$candidate" == https://www.lua.org/ftp/* ]]; then
      candidate_retries=1
    fi
    echo "[blfs-sources] trying: $candidate"
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
    if command -v curl >/dev/null 2>&1 &&
      curl \
        --fail \
        --location \
        --retry "$candidate_retries" \
        --retry-all-errors \
        --connect-timeout 30 \
        --max-time 180 \
        --output "$partial" \
        "$candidate" &&
      printf '%s  %s\n' "$checksum" "$partial" |
        md5sum --check --status; then
      mv "$partial" "$target"
      return 0
    fi
    rm -f "$partial"
    echo "[blfs-sources] mirror failed: $candidate" >&2
  done

  echo "[blfs-sources] all mirrors failed: $(basename "$target")" >&2
  return 1
}

while IFS=$'\t' read -r checksum filename url; do
  [[ -z "$checksum" || "${checksum:0:1}" == "#" ]] && continue
  target="$output_dir/$filename"
  cached_target="$download_cache/$filename"
  if [[ -f "$target" ]] &&
    printf '%s  %s\n' "$checksum" "$target" | md5sum --check --status; then
    echo "[blfs-sources] cache hit: $filename"
    continue
  fi
  if [[ -f "$cached_target" ]] &&
    printf '%s  %s\n' "$checksum" "$cached_target" |
      md5sum --check --status; then
    echo "[blfs-sources] persistent cache hit: $filename"
    cp "$cached_target" "$target"
    continue
  fi
  echo "[blfs-sources] downloading: $filename"
  download_verified "$checksum" "$target" "$url"
  cp "$target" "$cached_target"
done <"$manifest"

generate_cargo_vendor_archive() {
  local lock_file=$1
  local archive=$2
  local crate_root
  local crate_manifest
  local name version checksum source crate_file crate_url

  crate_root=$(mktemp -d)
  crate_manifest="$crate_root/crates.tsv"
  awk '
    /^\[\[package\]\]$/ {
      if (source ~ /^registry\+/) print checksum "\t" name "\t" version
      name = version = source = checksum = ""
      next
    }
    /^name = "/ {
      value = $0
      sub(/^name = "/, "", value)
      sub(/"$/, "", value)
      name = value
      next
    }
    /^version = "/ {
      value = $0
      sub(/^version = "/, "", value)
      sub(/"$/, "", value)
      version = value
      next
    }
    /^source = "/ {
      value = $0
      sub(/^source = "/, "", value)
      sub(/"$/, "", value)
      source = value
      next
    }
    /^checksum = "/ {
      value = $0
      sub(/^checksum = "/, "", value)
      sub(/"$/, "", value)
      checksum = value
      next
    }
    END {
      if (source ~ /^registry\+/) print checksum "\t" name "\t" version
    }
  ' "$lock_file" >"$crate_manifest"

  while IFS=$'\t' read -r checksum name version; do
    [[ "$checksum" =~ ^[0-9a-f]{64}$ &&
       "$name" =~ ^[A-Za-z0-9_+-]+$ &&
       "$version" =~ ^[A-Za-z0-9.+_-]+$ ]] || {
      echo "[blfs-sources] invalid Cargo.lock package: $name $version" >&2
      return 1
    }
    crate_file="$crate_root/$name-$version.crate"
    crate_url="https://static.crates.io/crates/$name/$name-$version.crate"
    echo "[blfs-sources] downloading crate: $name $version"
    wget --quiet --tries="$retries" --timeout=30 \
      --output-document="$crate_file.part" "$crate_url"
    printf '%s  %s\n' "$checksum" "$crate_file.part" |
      sha256sum --check --status
    mv "$crate_file.part" "$crate_file"
  done <"$crate_manifest"

  rm "$crate_manifest"
  tar --sort=name --mtime='UTC 2026-08-06' --owner=0 --group=0 \
    --numeric-owner -C "$crate_root" -cf - . |
    zstd -q -19 -T0 -o "$archive"
  rm -rf "$crate_root"
}

if [[ -f "$output_dir/cargo-c-0.10.24-Cargo.lock" ]]; then
  cargo_archive="$output_dir/cargo-c-0.10.24-crates.tar.zst"
  if [[ ! -f "$cargo_archive" ]]; then
    generate_cargo_vendor_archive \
      "$output_dir/cargo-c-0.10.24-Cargo.lock" "$cargo_archive"
  fi
  cargo_archive_md5=$(md5sum "$cargo_archive" | awk '{print $1}')
  printf '%s\t%s\t%s\n' \
    "$cargo_archive_md5" \
    "cargo-c-0.10.24-crates.tar.zst" \
    "generated-from:cargo-c-0.10.24-Cargo.lock" \
    >>"$output_dir/sources.tsv"
fi

if [[ -f "$output_dir/librsvg-2.62.3.tar.xz" ]]; then
  librsvg_lock="$output_dir/librsvg-2.62.3-Cargo.lock"
  tar -xOf "$output_dir/librsvg-2.62.3.tar.xz" \
    librsvg-2.62.3/Cargo.lock >"$librsvg_lock"
  librsvg_archive="$output_dir/librsvg-2.62.3-crates.tar.zst"
  generate_cargo_vendor_archive "$librsvg_lock" "$librsvg_archive"
  librsvg_lock_md5=$(md5sum "$librsvg_lock" | awk '{print $1}')
  librsvg_archive_md5=$(md5sum "$librsvg_archive" | awk '{print $1}')
  printf '%s\t%s\t%s\n' \
    "$librsvg_lock_md5" \
    "librsvg-2.62.3-Cargo.lock" \
    "extracted-from:librsvg-2.62.3.tar.xz" \
    >>"$output_dir/sources.tsv"
  printf '%s\t%s\t%s\n' \
    "$librsvg_archive_md5" \
    "librsvg-2.62.3-crates.tar.zst" \
    "generated-from:librsvg-2.62.3-Cargo.lock" \
    >>"$output_dir/sources.tsv"
fi

sed '/^#/d' "$manifest" >>"$output_dir/sources.tsv"
(
  cd "$output_dir"
  awk -F '\t' '!/^#/ && NF == 3 { values[$2] = $1 }
    END { for (file in values) print values[file] "  " file }' \
    sources.tsv | LC_ALL=C sort -k2 >MD5SUMS
  md5sum --check MD5SUMS
  find . -maxdepth 1 -type f -printf '%f\n' | LC_ALL=C sort >FILES
)

cat >"$output_root/opt/xbee-lfs-native/blfs-sources-metadata.yaml" <<EOF
schema-version: 1
blfs-book: "13.0"
checksum: md5
manifest: sources/sources.tsv
EOF
