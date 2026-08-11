#!/usr/bin/env bash
set -euo pipefail
site_dir="$STAGE/usr/lib/python3.14/site-packages"
install -d "$site_dir" "$STAGE/usr/bin"
cp -a pygments "$site_dir/"
install -m755 /dev/stdin "$STAGE/usr/bin/pygmentize" <<'EOF'
#!/bin/sh
exec python3 -m pygments.cmdline "$@"
EOF
test -x "$STAGE/usr/bin/pygmentize"
