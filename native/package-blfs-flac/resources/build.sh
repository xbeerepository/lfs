#!/usr/bin/env bash
set -euo pipefail

./configure \
  --prefix=/usr \
  --disable-thorough-tests \
  --docdir=/usr/share/doc/flac-1.5.0
make -j"$JOBS"
# The metadata permission test deliberately fails when executed as root.
# Package builds run as root in the XBee chroot, so execute the test suite as
# the unprivileged nobody user, like a normal BLFS build.
chown -R nobody .
su nobody -s /bin/bash -c "make check"
make DESTDIR="$STAGE" install
