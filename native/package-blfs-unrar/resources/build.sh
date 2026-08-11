#!/usr/bin/env bash
set -euo pipefail
make -f makefile -j"$JOBS"
install -Dm755 unrar "$STAGE/usr/bin/unrar"
