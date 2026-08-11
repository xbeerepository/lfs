#!/usr/bin/env bash
set -euo pipefail

xsl_dir="$STAGE/usr/share/xml/docbook/xsl-stylesheets-nons-$PACKAGE_VERSION"
doc_dir="$STAGE/usr/share/doc/docbook-xsl-nons-$PACKAGE_VERSION"

patch -Np1 -i ../docbook-xsl-nons-1.79.2-stack_fix-1.patch
install -d -m 0755 "$xsl_dir" "$doc_dir" "$STAGE/.xbpkg-hooks"
cp -R \
  VERSION assembly common eclipse epub epub3 extensions fo \
  highlighting html htmlhelp images javahelp lib manpages params \
  profiling roundtrip slides template tests tools webhelp website \
  xhtml xhtml-1_1 xhtml5 "$xsl_dir"
ln -sfn VERSION "$xsl_dir/VERSION.xsl"
install -m 0644 README "$doc_dir/README.txt"
install -m 0644 RELEASE-NOTES* NEWS* "$doc_dir"

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
sed '/<!-- xbpkg:docbook-xsl-nons begin -->/,/<!-- xbpkg:docbook-xsl-nons end -->/d' \
  "$catalog" >"$temporary"
directory="/usr/share/xml/docbook/xsl-stylesheets-nons-$XBPKG_PACKAGE_VERSION"
block="$catalog.xbpkg-block.$$"
{
  printf '%s\n' '  <!-- xbpkg:docbook-xsl-nons begin -->'
  for uri in \
    "http://cdn.docbook.org/release/xsl-nons/$XBPKG_PACKAGE_VERSION" \
    "https://cdn.docbook.org/release/xsl-nons/$XBPKG_PACKAGE_VERSION" \
    http://cdn.docbook.org/release/xsl-nons/current \
    https://cdn.docbook.org/release/xsl-nons/current \
    http://docbook.sourceforge.net/release/xsl/current; do
    printf '  <rewriteSystem systemIdStartString="%s" rewritePrefix="%s"/>\n' \
      "$uri" "$directory"
    printf '  <rewriteURI uriStartString="%s" rewritePrefix="%s"/>\n' \
      "$uri" "$directory"
  done
  printf '%s\n' '  <!-- xbpkg:docbook-xsl-nons end -->'
} >"$block"
sed -i "/<\\/catalog>/e cat $block" "$temporary"
rm -f "$block"
mv -f "$temporary" "$catalog"
EOF
cat >"$STAGE/.xbpkg-hooks/pre-remove" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
catalog="${XBPKG_ROOT%/}/etc/xml/catalog"
[[ -f "$catalog" ]] || exit 0
temporary="$catalog.xbpkg.$$"
sed '/<!-- xbpkg:docbook-xsl-nons begin -->/,/<!-- xbpkg:docbook-xsl-nons end -->/d' \
  "$catalog" >"$temporary"
mv -f "$temporary" "$catalog"
EOF
printf '%s\n' /etc/xml/catalog >"$STAGE/.xbpkg-hooks/paths"
