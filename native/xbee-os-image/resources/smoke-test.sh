#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: smoke-test.sh DOCKER_ARCHIVE" >&2
  exit 2
fi

archive=$1
[[ -f "$archive" ]]
docker load --input "$archive"
docker run --rm xbee-os:13.0 /bin/bash -lc '
  set -e
  . /etc/os-release
  test "$ID" = xbee-os
  test "$VERSION_ID" = 13.0
  command -v xbpkg >/dev/null
  xbpkg check
  xbpkg list | grep -q "^bash "
  ! xbpkg list | grep -Eq "^(grub|linux-kernel|linux-modules|openssh|systemd) "
'
