#!/usr/bin/env bash
set -euo pipefail
(for component in Bundles/{Alone,Alone7z,Format7zF,SFXCon} UI/Console; do
  make -C "CPP/7zip/$component" -f ../../cmpl_gcc.mak -j"$JOBS"
done)
install -d "$STAGE/usr/lib/7zip" "$STAGE/usr/bin" "$STAGE/usr/share/doc/7zip-26.01"
install -m755 CPP/7zip/Bundles/Alone/b/g/7za \
  CPP/7zip/Bundles/Alone7z/b/g/7zr \
  CPP/7zip/Bundles/Format7zF/b/g/7z.so \
  CPP/7zip/UI/Console/b/g/7z "$STAGE/usr/lib/7zip"
install -m755 CPP/7zip/Bundles/SFXCon/b/g/7zCon "$STAGE/usr/lib/7zip/7zCon.sfx"
for program in 7z 7za 7zr; do
  printf '#!/bin/sh\nexec /usr/lib/7zip/%s "$@"\n' "$program" >"$STAGE/usr/bin/$program"
  chmod 755 "$STAGE/usr/bin/$program"
done
cp -a DOC/. "$STAGE/usr/share/doc/7zip-26.01/"
test -x "$STAGE/usr/bin/7z"
