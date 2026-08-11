#!/usr/bin/env bash
set -euo pipefail

grep -rl '^#!.*python$' . | xargs -r sed -i '1s/python/&3/'
meson setup build \
  --prefix=/usr \
  --buildtype=release \
  --wrap-mode=nofallback \
  -Dlibaudit=no \
  -Dnmtui=false \
  -Dovs=false \
  -Dppp=false \
  -Dnbft=false \
  -Dselinux=false \
  -Dsession_tracking=systemd \
  -Dmodem_manager=false \
  -Dsystemdsystemunitdir=/usr/lib/systemd/system \
  -Dsystemdsystemgeneratordir=/usr/lib/systemd/system-generators \
  -Dsystemd_journal=true \
  -Dnm_cloud_setup=false \
  -Dclat=false \
  -Dqt=false \
  -Dcrypto=null \
  -Dconcheck=false \
  -Dintrospection=false \
  -Ddocs=false \
  -Dtests=no
ninja -C build -j"$JOBS"
DESTDIR="$STAGE" ninja -C build install
install -Dm644 /dev/stdin "$STAGE/etc/NetworkManager/NetworkManager.conf" <<'EOF'
[main]
plugins=keyfile
dhcp=internal
auth-polkit=true
EOF
