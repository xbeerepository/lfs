#!/usr/bin/env bash
set -euo pipefail

meson setup build --prefix=/usr --buildtype=release --wrap-mode=nofallback \
  -Dx11_backend=false -Dwayland_backend=true \
  -Dintrospection=true -Dgtk_doc=false -Dman=false \
  -Ddemos=false -Dexamples=false -Dtests=false \
  -Dprint_backends=file -Dxinerama=no -Dcolord=no
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
