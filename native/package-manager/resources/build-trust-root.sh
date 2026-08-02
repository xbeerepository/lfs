#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 6 ]]; then
  echo "usage: build-trust-root.sh OUT VERSION EXPIRES REPOSITORY_KEYS RELEASE_KEYS REVOCATION_KEYS" >&2
  exit 2
fi

output=$1
version=$2
expires_at=$3
repository_keys=$4
release_keys=$5
revocation_keys=$6
signing_keys=${XBPKG_ROOT_SIGNING_KEYS:-}
threshold=${XBPKG_ROOT_THRESHOLD:-2}

[[ "$version" =~ ^[1-9][0-9]*$ &&
   "$threshold" =~ ^[1-9][0-9]*$ &&
   "$expires_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ &&
   -n "$signing_keys" ]] || {
  echo "invalid trust-root configuration" >&2
  exit 2
}

IFS=: read -r -a private_keys <<<"$signing_keys"
((${#private_keys[@]} >= threshold)) || {
  echo "root signing threshold exceeds supplied keys" >&2
  exit 1
}

rm -rf "$output"
mkdir -p "$output/root-keys" "$output/TRUST-ROOT.signatures"
root_ids=()
for private_key in "${private_keys[@]}"; do
  [[ -f "$private_key" && ! -L "$private_key" ]] || {
    echo "root signing key not found: $private_key" >&2
    exit 1
  }
  public_der=$(mktemp)
  openssl pkey -in "$private_key" -pubout -outform DER \
    -out "$public_der"
  key_id=$(sha256sum "$public_der" | awk '{print $1}')
  openssl pkey -in "$private_key" -pubout \
    -out "$output/root-keys/$key_id.pem"
  root_ids+=("$key_id")
  rm -f "$public_der"
done

join_sorted() {
  printf '%s\n' "$@" | LC_ALL=C sort -u | paste -sd, -
}

root_key_ids=$(join_sorted "${root_ids[@]}")
cat >"$output/TRUST-ROOT" <<EOF
schema-version: 1
version: $version
expires-at: "$expires_at"
root-threshold: $threshold
root-keys: "$root_key_ids"
repository-keys: "$repository_keys"
release-keys: "$release_keys"
revocation-keys: "$revocation_keys"
revoked-keys: ""
EOF

for index in "${!private_keys[@]}"; do
  openssl pkeyutl -sign -inkey "${private_keys[index]}" -rawin \
    -in "$output/TRUST-ROOT" \
    -out "$output/TRUST-ROOT.signatures/${root_ids[index]}.sig"
done
printf 'built TRUST-ROOT version %s with threshold %s\n' \
  "$version" "$threshold"
