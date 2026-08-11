#!/usr/bin/env bash
set -euo pipefail

install -d "$STAGE/usr/share/fonts/liberation" "$STAGE/usr/share/licenses/liberation-fonts"
install -m 0644 *.ttf "$STAGE/usr/share/fonts/liberation/"
install -m 0644 LICENSE "$STAGE/usr/share/licenses/liberation-fonts/"
