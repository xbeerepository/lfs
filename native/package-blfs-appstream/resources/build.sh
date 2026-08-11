#!/usr/bin/env bash
set -euo pipefail

cat > docbook-catalog.xml <<'EOF'
<?xml version="1.0"?>
<!DOCTYPE catalog PUBLIC "-//OASIS//DTD Entity Resolution XML Catalog V1.0//EN"
  "http://www.oasis-open.org/committees/entity/release/1.0/catalog.dtd">
<catalog xmlns="urn:oasis:names:tc:entity:xmlns:xml:catalog">
  <rewriteURI
    uriStartString="http://docbook.sourceforge.net/release/xsl/current"
    rewritePrefix="/usr/share/xml/docbook/xsl-stylesheets-nons-1.79.2"/>
  <rewriteSystem
    systemIdStartString="http://www.oasis-open.org/docbook/xml/4.5"
    rewritePrefix="/usr/share/xml/docbook/xml-dtd-4.5"/>
  <rewriteURI
    uriStartString="http://www.oasis-open.org/docbook/xml/4.5"
    rewritePrefix="/usr/share/xml/docbook/xml-dtd-4.5"/>
</catalog>
EOF
export XML_CATALOG_FILES="$PWD/docbook-catalog.xml"

meson setup build --prefix=/usr --buildtype=release \
  -Dapidocs=false -Dbash-completion=false -Dgir=false -Dstemming=false \
  -Dsystemd=false
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
test -x "$STAGE/usr/bin/appstreamcli"
