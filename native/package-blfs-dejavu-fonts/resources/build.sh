#!/usr/bin/env bash
set -euo pipefail

install -d "$STAGE/usr/share/fonts/dejavu" "$STAGE/usr/share/licenses/dejavu-fonts"
install -m 0644 ttf/*.ttf "$STAGE/usr/share/fonts/dejavu/"
install -m 0644 LICENSE "$STAGE/usr/share/licenses/dejavu-fonts/"
