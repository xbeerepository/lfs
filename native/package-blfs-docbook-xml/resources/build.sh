#!/usr/bin/env bash
set -euo pipefail

dtd_dir="$STAGE/usr/share/xml/docbook/xml-dtd-4.5"
catalog="$dtd_dir/catalog.xml"
system_catalog="$STAGE/etc/xml/catalog"

install -d -m 0755 "$dtd_dir" "$STAGE/.xbpkg-hooks"
cp -af --no-preserve=ownership \
  catalog.xml docbook.cat ./*.dtd ent ./*.mod "$dtd_dir"

xmlcatalog --noout --add rewriteSystem \
  http://www.oasis-open.org/docbook/xml/4.5 \
  file:///usr/share/xml/docbook/xml-dtd-4.5 "$catalog"
xmlcatalog --noout --add rewriteURI \
  http://www.oasis-open.org/docbook/xml/4.5 \
  file:///usr/share/xml/docbook/xml-dtd-4.5 "$catalog"

for dtd_version in 4.1.2 4.2 4.3 4.4; do
  xmlcatalog --noout --add public \
    "-//OASIS//DTD DocBook XML V$dtd_version//EN" \
    "http://www.oasis-open.org/docbook/xml/$dtd_version/docbookx.dtd" \
    "$catalog"
  xmlcatalog --noout --add rewriteSystem \
    "http://www.oasis-open.org/docbook/xml/$dtd_version" \
    file:///usr/share/xml/docbook/xml-dtd-4.5 "$catalog"
  xmlcatalog --noout --add rewriteURI \
    "http://www.oasis-open.org/docbook/xml/$dtd_version" \
    file:///usr/share/xml/docbook/xml-dtd-4.5 "$catalog"
done

cat >"$STAGE/.xbpkg-hooks/post-install" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
catalog="${XBPKG_ROOT%/}/etc/xml/catalog"
mkdir -p "$(dirname "$catalog")"
if [[ ! -f "$catalog" ]]; then
  cat >"$catalog" <<'XML'
<?xml version="1.0"?>
<catalog xmlns="urn:oasis:names:tc:entity:xmlns:xml:catalog">
</catalog>
XML
fi
temporary="$catalog.xbpkg.$$"
sed '/<!-- xbpkg:docbook-xml begin -->/,/<!-- xbpkg:docbook-xml end -->/d' \
  "$catalog" >"$temporary"
sed -i '/<\/catalog>/i\
  <!-- xbpkg:docbook-xml begin -->\
  <delegatePublic publicIdStartString="-//OASIS//ENTITIES DocBook XML" catalog="file:///usr/share/xml/docbook/xml-dtd-4.5/catalog.xml"/>\
  <delegatePublic publicIdStartString="-//OASIS//DTD DocBook XML" catalog="file:///usr/share/xml/docbook/xml-dtd-4.5/catalog.xml"/>\
  <delegateSystem systemIdStartString="http://www.oasis-open.org/docbook/" catalog="file:///usr/share/xml/docbook/xml-dtd-4.5/catalog.xml"/>\
  <delegateURI uriStartString="http://www.oasis-open.org/docbook/" catalog="file:///usr/share/xml/docbook/xml-dtd-4.5/catalog.xml"/>\
  <!-- xbpkg:docbook-xml end -->' "$temporary"
mv -f "$temporary" "$catalog"
EOF
cat >"$STAGE/.xbpkg-hooks/pre-remove" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
catalog="${XBPKG_ROOT%/}/etc/xml/catalog"
[[ -f "$catalog" ]] || exit 0
temporary="$catalog.xbpkg.$$"
sed '/<!-- xbpkg:docbook-xml begin -->/,/<!-- xbpkg:docbook-xml end -->/d' \
  "$catalog" >"$temporary"
mv -f "$temporary" "$catalog"
EOF
printf '%s\n' /etc/xml/catalog >"$STAGE/.xbpkg-hooks/paths"
