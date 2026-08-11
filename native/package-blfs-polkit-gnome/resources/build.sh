#!/usr/bin/env bash
set -euo pipefail

patch -Np1 -i /sources/polkit-gnome-0.105-consolidated_fixes-1.patch
sed -i '/#include <gdk\/gdkx.h>/d' src/polkitgnomeauthenticator.c
perl -0pi -e 's/  GdkWindow \*window =.*?\n  password/  gtk_window_present (GTK_WINDOW (authenticator->dialog));\n  password/s' \
  src/polkitgnomeauthenticator.c
./configure --prefix=/usr --libexecdir=/usr/libexec
make -j"$JOBS"
make DESTDIR="$STAGE" install
