#!/usr/bin/env bash
set -euo pipefail

sed -i 's/groups$(EXEEXT) //' src/Makefile.in
find man -name Makefile.in -exec sed -i 's/groups\.1 / /' {} \;
find man -name Makefile.in -exec sed -i 's/getspnam\.3 / /' {} \;
find man -name Makefile.in -exec sed -i 's/passwd\.5 / /' {} \;
sed -e 's:#ENCRYPT_METHOD DES:ENCRYPT_METHOD YESCRYPT:' \
    -e 's:/var/spool/mail:/var/mail:' \
    -e '/PATH=/{s@/sbin:@@;s@/bin:@@}' \
    -i etc/login.defs

./configure --sysconfdir=/etc \
  --disable-static \
  --without-libbsd \
  --with-bcrypt \
  --with-yescrypt
make -j"$JOBS"
make exec_prefix=/usr pamddir= DESTDIR="$STAGE" install
make -C man DESTDIR="$STAGE" install-man

install -d "$STAGE/etc/pam.d"
cat >"$STAGE/etc/pam.d/login" <<'EOF'
auth requisite pam_nologin.so
auth include system-auth
account include system-account
session include system-session
EOF
cat >"$STAGE/etc/pam.d/passwd" <<'EOF'
password include system-password
EOF
cat >"$STAGE/etc/pam.d/su" <<'EOF'
auth sufficient pam_rootok.so
auth include system-auth
account include system-account
session include system-session
EOF
cat >"$STAGE/etc/pam.d/chpasswd" <<'EOF'
auth sufficient pam_rootok.so
account include system-account
password include system-password
EOF
cp "$STAGE/etc/pam.d/chpasswd" "$STAGE/etc/pam.d/newusers"
cat >"$STAGE/etc/pam.d/chage" <<'EOF'
auth sufficient pam_rootok.so
account include system-account
EOF
for program in chfn chgpasswd chsh groupadd groupdel groupmems groupmod \
  useradd userdel usermod; do
  cp "$STAGE/etc/pam.d/chage" "$STAGE/etc/pam.d/$program"
done
