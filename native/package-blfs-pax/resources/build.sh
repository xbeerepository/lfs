#!/usr/bin/env bash
set -euo pipefail
CC=gcc CFLAGS='-O2' sh ./Build.sh -r -tpax -j

install -Dm755 pax "$STAGE/usr/bin/pax"
install -Dm755 paxcpio "$STAGE/usr/bin/paxcpio"
install -Dm755 paxtar "$STAGE/usr/bin/paxtar"
install -Dm644 pax.1 "$STAGE/usr/share/man/man1/pax.1"
install -Dm644 cpio.1 "$STAGE/usr/share/man/man1/paxcpio.1"
install -Dm644 tar.1 "$STAGE/usr/share/man/man1/paxtar.1"

test -x "$STAGE/usr/bin/pax"
test -x "$STAGE/usr/bin/paxcpio"
test -x "$STAGE/usr/bin/paxtar"
