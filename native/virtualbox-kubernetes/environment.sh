#!/usr/bin/env bash
set -euo pipefail

env_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repository_root=$(cd -- "$env_dir/../.." && pwd)
projects_root=$(dirname -- "$repository_root")
xbee_bin=${XBEE_BIN:-xbee}
provider_source=${XBEE_VIRTUALBOX_SOURCE:-"$projects_root/virtualbox-provider"}
provider_binary=${XBEE_PROVIDER_BINARY:-"$provider_source/dist/xbee-virtualbox"}
guest_binary=${XBEE_GUEST_BINARY:-"$(command -v "$xbee_bin")"}
vmdk=${XBEE_KUBERNETES_VMDK:-"$repository_root/dist/kubernetes-os-v1.37.0/kubernetes-os-13.0-x86_64-virtualbox.vmdk"}
cached_vmdk="$HOME/.xbee/cache-artefacts/github.com/xbeerepository/lfs/releases/download/v0.3.3/kubernetes-os-13.0-x86_64-virtualbox.vmdk"

prepare_local_runtime() {
  if [[ ! -x "$provider_binary" ]]; then
    [[ -f "$provider_source/go.mod" ]] || {
      printf 'VirtualBox provider source not found: %s\n' "$provider_source" >&2
      exit 1
    }
    mkdir -p "$(dirname -- "$provider_binary")"
    (cd "$provider_source" && go build -o "$provider_binary" ./main)
  fi

  [[ -f "$vmdk" ]] || {
    printf 'Kubernetes VMDK not found: %s\n' "$vmdk" >&2
    exit 1
  }
  mkdir -p "$(dirname -- "$cached_vmdk")"
  if [[ -e "$cached_vmdk" || -L "$cached_vmdk" ]]; then
    [[ "$(readlink -f -- "$cached_vmdk")" == "$(readlink -f -- "$vmdk")" ]] || {
      printf 'XBee cache entry already exists and does not reference %s: %s\n' "$vmdk" "$cached_vmdk" >&2
      exit 1
    }
  else
    ln -s "$vmdk" "$cached_vmdk"
  fi

  export XBEE_PROVIDER_BINARY="$provider_binary"
  export XBEE_GUEST_BINARY="$guest_binary"
}

cd "$env_dir"

case "${1:-}" in
  start)
    prepare_local_runtime
    "$xbee_bin" pack --non-interactive
    "$xbee_bin" up
    ;;
  stop)
    prepare_local_runtime
    "$xbee_bin" down
    ;;
  restart)
    prepare_local_runtime
    "$xbee_bin" down
    "$xbee_bin" pack --non-interactive
    "$xbee_bin" up
    ;;
  *)
    printf 'Usage: %s {start|stop|restart}\n' "${0##*/}" >&2
    exit 2
    ;;
esac
