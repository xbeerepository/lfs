#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

export XBEELFS_HOSTNAME=${XBEELFS_HOSTNAME:-xbee-lfs-sway}
export XBEELFS_PACKAGE_COUNT=169
export XBEELFS_PROFILE=desktop-sway

exec "$script_dir/../../package-system/resources/smoke-test.sh" "$@"
