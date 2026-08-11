#!/usr/bin/env bash
set -euo pipefail
pip3 wheel -w dist --no-build-isolation --no-deps --no-cache-dir "$PWD"
pip3 install --root "$STAGE" --no-index --find-links dist --no-user glad2
