#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
system_file="$repo_root/native/xbee-os/xbee-pack-system.yaml"
env_file="$repo_root/native/virtualbox-xbee-os/xbee-env.yaml"
pack_file="$repo_root/native/virtualbox-xbee-os/pack/xbee-pack.yaml"

grep -Fq 'container: "{{ .image.container }}:{{ .image.tag }}"' "$system_file"
grep -Fq 'container: xbee-os' "$system_file"
grep -Fq 'tag: "13.0"' "$system_file"
grep -Fq 'xbee-os-13.0-x86_64-virtualbox.vmdk' "$system_file"
grep -Fq 'system: ../xbee-os' "$env_file"
grep -Fq 'require: ../../xbee-os' "$pack_file"

if grep -Fq 'system:' "$repo_root/native/xbee-os-virtualbox/xbee-pack-system.yaml" 2>/dev/null; then
  echo "legacy xbee-os-virtualbox pack still exists" >&2
  exit 1
fi

echo "xbee-os Docker and VirtualBox provider references are coherent"
