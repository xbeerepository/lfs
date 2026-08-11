#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: prepare-source.sh SOURCES RESOURCES OUTPUT" >&2
  exit 2
fi

sources=$1
resources=$2
output=$3
bundle_name=${output%.tar.xz}
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
bundle_dir="$work_dir/$bundle_name"
install -d "$bundle_dir"

while read -r checksum file; do
  [[ -n "${file:-}" ]] || continue
  [[ -f "$sources/$file" ]] || {
    echo "missing KDE Frameworks source: $file" >&2
    exit 1
  }
  actual=$(md5sum "$sources/$file" | awk '{print $1}')
  [[ "$actual" == "$checksum" ]] || {
    echo "KDE Frameworks checksum mismatch: $file" >&2
    exit 1
  }
  cp "$sources/$file" "$bundle_dir/"
done < "$resources/frameworks.md5"

cp "$resources/frameworks.md5" "$bundle_dir/"
tar -C "$work_dir" -cJf "$sources/$output" "$bundle_name"
