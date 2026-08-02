#!/usr/bin/env bash
set -euo pipefail

ignore_expiration=false
if [[ ${1:-} == --ignore-expiration ]]; then
  ignore_expiration=true
  shift
fi
if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "usage: verify-release.sh [--ignore-expiration] RELEASE_DIR TRUSTED_KEY [REVOKED_KEYS]" >&2
  exit 2
fi

release_dir=${1%/}
trusted_key=$2
revoked_keys=${3:-}
manifest="$release_dir/ARTIFACTS"
signature="$release_dir/ARTIFACTS.sig"
key_id_file="$release_dir/ARTIFACTS.keyid"

[[ -d "$release_dir" &&
   -f "$manifest" && ! -L "$manifest" &&
   -f "$signature" && ! -L "$signature" &&
   -f "$key_id_file" && ! -L "$key_id_file" &&
   -f "$trusted_key" && ! -L "$trusted_key" ]] || {
  echo "release verification inputs are incomplete" >&2
  exit 1
}
for command_name in date openssl sha256sum stat; do
  command -v "$command_name" >/dev/null || {
    echo "required command not found: $command_name" >&2
    exit 1
  }
done

expected_key_id=$(head -n 1 "$key_id_file")
actual_key_id=$(openssl pkey -pubin -in "$trusted_key" -outform DER \
  2>/dev/null | sha256sum | awk '{print $1}')
[[ "$expected_key_id" =~ ^[[:xdigit:]]{64}$ &&
   "$actual_key_id" == "$expected_key_id" ]] || {
  echo "release signing key identifier mismatch" >&2
  exit 1
}
if [[ -n "$revoked_keys" ]]; then
  [[ -f "$revoked_keys" && ! -L "$revoked_keys" ]] || {
    echo "invalid release revoked key list" >&2
    exit 1
  }
  if grep -Ev '^[[:space:]]*(#|$)' "$revoked_keys" |
    grep -Fqx -- "$expected_key_id"; then
    echo "release signing key is revoked: $expected_key_id" >&2
    exit 1
  fi
fi
openssl pkeyutl -verify -pubin -inkey "$trusted_key" \
  -sigfile "$signature" -rawin -in "$manifest" >/dev/null 2>&1 || {
  echo "release signature verification failed" >&2
  exit 1
}

declare -A expected_files=()
while read -r expected_sha expected_size filename extra; do
  [[ -z "${extra:-}" &&
     "$expected_sha" =~ ^[[:xdigit:]]{64}$ &&
     "$expected_size" =~ ^[0-9]+$ &&
     "$filename" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ &&
     -z ${expected_files["$filename"]:-} ]] || {
    echo "invalid ARTIFACTS entry: $expected_sha $expected_size $filename" >&2
    exit 1
  }
  artefact="$release_dir/$filename"
  [[ -f "$artefact" && ! -L "$artefact" ]] || {
    echo "release artefact is missing: $filename" >&2
    exit 1
  }
  actual_size=$(stat -c %s "$artefact")
  actual_sha=$(sha256sum "$artefact" | awk '{print $1}')
  [[ "$actual_size" == "$expected_size" ]] || {
    echo "release artefact size mismatch: $filename" >&2
    exit 1
  }
  [[ "$actual_sha" == "$expected_sha" ]] || {
    echo "release artefact checksum mismatch: $filename" >&2
    exit 1
  }
  expected_files["$filename"]=1
done <"$manifest"
((${#expected_files[@]} > 0)) || {
  echo "ARTIFACTS is empty" >&2
  exit 1
}

for artefact in "$release_dir"/*; do
  [[ -f "$artefact" && ! -L "$artefact" ]] || continue
  filename=$(basename "$artefact")
  case "$filename" in
    ARTIFACTS|ARTIFACTS.sig|ARTIFACTS.keyid|release-ed25519-public.pem)
      ;;
    *)
      [[ -n ${expected_files["$filename"]:-} ]] || {
        echo "unexpected release artefact: $filename" >&2
        exit 1
      }
      ;;
  esac
done

freshness="$release_dir/ARTIFACTS.release"
[[ -n ${expected_files["ARTIFACTS.release"]:-} ]] || {
  echo "ARTIFACTS.release is not covered by ARTIFACTS" >&2
  exit 1
}
published_at=$(sed -n 's/^published-at:[[:space:]]*//p' "$freshness" |
  head -n 1 | tr -d '"')
expires_at=$(sed -n 's/^expires-at:[[:space:]]*//p' "$freshness" |
  head -n 1 | tr -d '"')
[[ "$published_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ &&
   "$expires_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || {
  echo "invalid release freshness metadata" >&2
  exit 1
}
published_epoch=$(date -u -d "$published_at" +%s 2>/dev/null) ||
  { echo "invalid release publication date" >&2; exit 1; }
expires_epoch=$(date -u -d "$expires_at" +%s 2>/dev/null) ||
  { echo "invalid release expiration date" >&2; exit 1; }
((expires_epoch > published_epoch)) ||
  { echo "release expiration precedes publication" >&2; exit 1; }
if [[ "$ignore_expiration" == false ]]; then
  now_epoch=$(date -u +%s)
  ((published_epoch <= now_epoch + 86400)) ||
    { echo "release publication date is in the future: $published_at" >&2; exit 1; }
  ((expires_epoch >= now_epoch)) ||
    { echo "release metadata expired at $expires_at" >&2; exit 1; }
fi

printf 'verified release artifacts with key %s\n' "$expected_key_id"
