#!/usr/bin/env bash
set -euo pipefail
python3 -m pip wheel -w dist --no-build-isolation --no-deps --no-cache-dir .
python3 -m pip install --root "$STAGE" --prefix /usr --no-index --find-links dist --no-user lxml
test -d "$STAGE/usr/lib/python3.14/site-packages/lxml"
