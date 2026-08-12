#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
pack_dir="${repo_root}/native/xbee-os"
test_cache=$(mktemp -d "${TMPDIR:-/tmp}/xbee-cold-cache.XXXXXX")
test_log=$(mktemp "${TMPDIR:-/tmp}/xbee-cold-cache.XXXXXX.log")
cleanup() {
  find "${test_cache}" -depth -delete
  find "${test_log}" -delete
}
trap cleanup EXIT

if ! (cd "${pack_dir}" && script --quiet --return \
  --command "env XBEE_INTERNAL_DIR='${test_cache}' xbee pack" /dev/null) \
  2>&1 | tee "${test_log}"; then
  echo "cold-cache pack failed" >&2
  exit 1
fi

if ! grep -Fq "Remote artefact cache hit" "${test_log}"; then
  echo "cold-cache pack did not use a remote builder artefact" >&2
  exit 1
fi

if grep -Fq "[BUILDER] Executing build task" "${test_log}"; then
  echo "cold-cache pack unexpectedly executed a local builder" >&2
  exit 1
fi

if ! grep -Fq "[DOCKER] Tagged parent image" "${test_log}"; then
  echo "cold-cache pack did not create the system tag from its rootfs parent" >&2
  exit 1
fi

if grep -Eq 'Tagged parent image .* as .*-(provision|deploy):' "${test_log}"; then
  echo "cold-cache pack used an intermediate task suffix for its final image" >&2
  exit 1
fi

if ! grep -Eq 'Tagged parent image .* as xbee-os-13\.0:' "${test_log}"; then
  echo "cold-cache pack did not create the neutral xbee-os final image tag" >&2
  exit 1
fi

echo "cold-cache pack reused the remote cache and created a neutral final image tag"
