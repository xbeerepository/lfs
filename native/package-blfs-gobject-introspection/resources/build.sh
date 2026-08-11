#!/usr/bin/env bash
set -euo pipefail
# The cairo-disabled bootstrap package and the cairo-enabled build install an
# identical payload with gobject-introspection 1.86.0.  Keep the public package
# name as a dependency-only compatibility package instead of shipping every
# file twice and causing ownership collisions.
test -x /usr/bin/g-ir-scanner
test -f /usr/lib/girepository-1.0/cairo-1.0.typelib

install -Dm644 /dev/null \
  "$STAGE/usr/share/doc/gobject-introspection-1.86.0/README.xbee"
printf '%s\n' \
  'The runtime payload is provided by gobject-introspection-core.' \
  'The cairo-enabled and bootstrap builds are byte-identical in this release.' \
  >"$STAGE/usr/share/doc/gobject-introspection-1.86.0/README.xbee"
