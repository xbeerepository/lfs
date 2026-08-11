#!/usr/bin/env bash
set -euo pipefail

cat > docbook-catalog.xml <<'EOF'
<?xml version="1.0"?>
<catalog xmlns="urn:oasis:names:tc:entity:xmlns:xml:catalog">
  <rewriteURI
    uriStartString="http://docbook.sourceforge.net/release/xsl/current"
    rewritePrefix="/usr/share/xml/docbook/xsl-stylesheets-nons-1.79.2"/>
</catalog>
EOF
export XML_CATALOG_FILES="$PWD/docbook-catalog.xml"

meson setup build --prefix=/usr --buildtype=release \
  -Dgtk_doc=false \
  -Dintrospection=false \
  -Dvapi=false
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
test -x "$STAGE/usr/bin/secret-tool"
