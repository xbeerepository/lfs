#!/usr/bin/env bash
set -euo pipefail
meson setup build --prefix=/usr --buildtype=release -Ddaemon_user=colord -Dintrospection=true -Dvapi=true -Dsystemd=true -Dlibcolordcompat=true -Dman=false -Ddocs=false -Dtests=false -Dargyllcms_sensor=false -Dbash_completion=false
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
install -Dm644 /dev/null "$STAGE/usr/lib/sysusers.d/colord.conf"
printf '%s\n' 'u colord - "Color management daemon" /var/lib/colord' > "$STAGE/usr/lib/sysusers.d/colord.conf"
test -x "$STAGE/usr/libexec/colord"
test -e "$STAGE/usr/share/vala/vapi/colord.vapi"
