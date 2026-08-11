#!/usr/bin/env bash
set -euo pipefail

./configure \
  --prefix=/usr \
  --with-gitconfig=/etc/gitconfig \
  --with-python=python3 \
  --with-libpcre2
make -j"$JOBS"
./git --version | grep -Fq "git version $PACKAGE_VERSION"
make DESTDIR="$STAGE" perllibdir=/usr/lib/perl5/5.42/site_perl install
test -x "$STAGE/usr/libexec/git-core/git-remote-http"
