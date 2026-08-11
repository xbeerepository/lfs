#!/usr/bin/env bash
set -euo pipefail

meson setup build \
  --prefix=/usr \
  --buildtype=release \
  --wrap-mode=nofallback
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install

install -d "$STAGE/etc/pam.d"
cat >"$STAGE/etc/pam.d/system-account" <<'EOF'
account required pam_unix.so
EOF
cat >"$STAGE/etc/pam.d/system-auth" <<'EOF'
auth required pam_unix.so
EOF
cat >"$STAGE/etc/pam.d/system-session" <<'EOF'
session required pam_unix.so
session required pam_loginuid.so
session optional pam_systemd.so
EOF
cat >"$STAGE/etc/pam.d/system-password" <<'EOF'
password required pam_unix.so yescrypt shadow try_first_pass
EOF
cat >"$STAGE/etc/pam.d/other" <<'EOF'
auth required pam_warn.so
auth required pam_deny.so
account required pam_warn.so
account required pam_deny.so
password required pam_warn.so
password required pam_deny.so
session required pam_warn.so
session required pam_deny.so
EOF

chmod 4755 "$STAGE/usr/sbin/unix_chkpwd"
