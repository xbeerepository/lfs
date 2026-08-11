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

./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var --disable-static --enable-available-modules
make -j"$JOBS"
make DESTDIR="$STAGE" install
test -x "$STAGE/usr/bin/udisksctl"
