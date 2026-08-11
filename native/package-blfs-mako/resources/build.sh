#!/usr/bin/env bash
set -euo pipefail

python3 -m pip wheel \
  --wheel-dir dist \
  --no-build-isolation \
  --no-deps \
  --no-cache-dir \
  "$PWD"
python3 -m pip install \
  --root="$STAGE" \
  --prefix=/usr \
  --no-index \
  --find-links=dist \
  --no-user \
  --no-deps \
  Mako
