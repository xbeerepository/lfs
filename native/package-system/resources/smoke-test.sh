#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: smoke-test.sh IMAGE.qcow2 SSH_PRIVATE_KEY [bios|uefi]

Boot a package-system image, provision it through a NoCloud cidata seed, and
verify SSH, systemd, networking, the package database, critical package
payloads, HTTPS, sudo, rsync, kernel modules, and clean shutdown.

Environment:
  XBEELFS_ADMIN_USER    guest administrator (default: xbee)
  XBEELFS_HOSTNAME      expected guest hostname (default: xbee-lfs)
  XBEELFS_MEMORY_MIB    VM memory in MiB (default: 2048)
  XBEELFS_SSH_PORT      host SSH port (default: 2222)
  XBEELFS_TIMEOUT       boot timeout in seconds (default: 360)
  XBEELFS_PACKAGE_COUNT expected installed package count (default: 208)
  XBEELFS_PROFILE       package profile under test (default: full)
  XBEELFS_KEEP_WORK     keep the temporary directory when set to true
EOF
}

if [[ $# -lt 2 || $# -gt 3 ]]; then
  usage
  exit 2
fi

image=$1
private_key=$2
firmware=${3:-bios}
admin_user=${XBEELFS_ADMIN_USER:-xbee}
expected_hostname=${XBEELFS_HOSTNAME:-xbee-lfs}
memory_mib=${XBEELFS_MEMORY_MIB:-2048}
ssh_port=${XBEELFS_SSH_PORT:-2222}
boot_timeout=${XBEELFS_TIMEOUT:-360}
package_count=${XBEELFS_PACKAGE_COUNT:-360}
profile=${XBEELFS_PROFILE:-full}
keep_work=${XBEELFS_KEEP_WORK:-false}

[[ -f "$image" ]] || {
  echo "package-system image not found: $image" >&2
  exit 2
}
[[ -f "$private_key" ]] || {
  echo "SSH private key not found: $private_key" >&2
  exit 2
}
[[ "$firmware" == bios || "$firmware" == uefi ]] || {
  echo "firmware must be bios or uefi" >&2
  exit 2
}
[[ "$admin_user" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || {
  echo "invalid administrator name: $admin_user" >&2
  exit 2
}
[[ "$expected_hostname" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || {
  echo "invalid expected hostname: $expected_hostname" >&2
  exit 2
}
for value_name in memory_mib ssh_port boot_timeout package_count; do
  value=${!value_name}
  [[ "$value" =~ ^[1-9][0-9]*$ ]] || {
    echo "$value_name must be a positive integer: $value" >&2
    exit 2
  }
done
for command_name in \
  openssl qemu-img qemu-system-x86_64 realpath ssh ssh-keygen timeout xorriso; do
  command -v "$command_name" >/dev/null || {
    echo "required command not found: $command_name" >&2
    exit 1
  }
done
if timeout 1 bash -c "</dev/tcp/127.0.0.1/$ssh_port" 2>/dev/null; then
  echo "host TCP port is already in use: $ssh_port" >&2
  exit 1
fi

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/xbee-lfs-package-smoke.XXXXXX")
qemu_pid=
cleanup() {
  if [[ -n "$qemu_pid" ]] && kill -0 "$qemu_pid" 2>/dev/null; then
    kill "$qemu_pid" 2>/dev/null || true
    wait "$qemu_pid" 2>/dev/null || true
  fi
  if [[ "$keep_work" == true ]]; then
    echo "package smoke-test work directory: $work_dir"
  else
    case "$work_dir" in
      "${TMPDIR:-/tmp}"/xbee-lfs-package-smoke.*)
        find "$work_dir" -depth -delete
        ;;
      *)
        echo "refusing unexpected cleanup path: $work_dir" >&2
        ;;
    esac
  fi
}
trap cleanup EXIT INT TERM

overlay="$work_dir/package-system.qcow2"
serial_log="$work_dir/serial.log"
pid_file="$work_dir/qemu.pid"
seed_dir="$work_dir/seed"
mkdir "$seed_dir"
ssh-keygen -y -f "$private_key" >"$seed_dir/public-key"
password_hash=$(openssl passwd -6 -salt xbeesmoketest 'xbee-smoke-password')
cat >"$seed_dir/meta-data" <<EOF
instance-id: xbee-package-smoke-001
local-hostname: $expected_hostname
EOF
{
  printf '%s\n' '#cloud-config' 'ssh_authorized_keys:'
  printf '  - %s\n' "$(<"$seed_dir/public-key")"
  printf "password_hash: '%s'\n" "$password_hash"
} >"$seed_dir/user-data"
xorriso -as mkisofs -quiet \
  -volid cidata -joliet -rock \
  -output "$work_dir/seed.iso" \
  "$seed_dir/user-data" "$seed_dir/meta-data"

firmware_args=()
if [[ "$firmware" == uefi ]]; then
  ovmf_code=/usr/share/OVMF/OVMF_CODE_4M.fd
  ovmf_vars=/usr/share/OVMF/OVMF_VARS_4M.fd
  if [[ ! -f "$ovmf_code" || ! -f "$ovmf_vars" ]]; then
    echo "OVMF firmware not found under /usr/share/OVMF" >&2
    exit 1
  fi
  cp "$ovmf_vars" "$work_dir/OVMF_VARS_4M.fd"
  firmware_args=(
    -drive "if=pflash,format=raw,readonly=on,file=$ovmf_code"
    -drive "if=pflash,format=raw,file=$work_dir/OVMF_VARS_4M.fd"
  )
fi
qemu-img create -q -f qcow2 -F qcow2 -b "$(realpath "$image")" "$overlay"

qemu-system-x86_64 \
  -name "xbee-lfs-package-smoke-$firmware" \
  -machine q35,accel=kvm:tcg \
  -cpu max \
  -m "$memory_mib" \
  -display none \
  -serial "file:$serial_log" \
  -monitor none \
  -daemonize \
  -pidfile "$pid_file" \
  "${firmware_args[@]}" \
  -drive "file=$overlay,if=virtio,format=qcow2" \
  -drive "file=$work_dir/seed.iso,media=cdrom,readonly=on" \
  -nic "user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:$ssh_port-:22"
qemu_pid=$(cat "$pid_file")

ssh_options=(
  -i "$private_key"
  -o BatchMode=yes
  -o ConnectTimeout=2
  -o LogLevel=ERROR
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -p "$ssh_port"
)
deadline=$((SECONDS + boot_timeout))
ssh_ready=false
while ((SECONDS < deadline)); do
  if ! kill -0 "$qemu_pid" 2>/dev/null; then
    echo "QEMU stopped before SSH became ready" >&2
    tail -n 160 "$serial_log" >&2
    exit 1
  fi
  if ssh "${ssh_options[@]}" -q "$admin_user@127.0.0.1" true \
      2>/dev/null; then
    ssh_ready=true
    break
  fi
  sleep 2
done
if [[ "$ssh_ready" != true ]]; then
  echo "SSH did not become ready within ${boot_timeout}s" >&2
  tail -n 160 "$serial_log" >&2
  exit 1
fi

ssh "${ssh_options[@]}" "$admin_user@127.0.0.1" \
  "EXPECTED_HOSTNAME='$expected_hostname' EXPECTED_PACKAGE_COUNT='$package_count' EXPECTED_PROFILE='$profile' bash -s" <<'EOF'
set -euo pipefail
trap 'echo "guest smoke check failed at line $LINENO: $BASH_COMMAND" >&2' ERR

test "$(hostname)" = "$EXPECTED_HOSTNAME"
test "$(uname -r)" = 6.18.10
timeout 180 sudo -n systemctl is-system-running --wait | grep -Fxq running
for service in sshd NetworkManager dbus systemd-logind xbee-nocloud; do
  test "$(sudo -n systemctl is-active "$service")" = active
done
test -f /var/lib/cloud/instance/boot-finished
test "$(< /var/lib/xbee-nocloud/instance-id)" = xbee-package-smoke-001
test "$(sudo -n systemctl --failed --no-legend | wc -l)" -eq 0
test "$(sudo -n id -u)" -eq 0
test "$(sudo -n xbpkg list | wc -l)" -eq "$EXPECTED_PACKAGE_COUNT"
test "$(passwd -S "$USER" | awk '{print $2}')" = P
grep -Fq "before-sleep 'swaylock -f -c 000000'" /usr/bin/xbee-swayidle
grep -Fq "polkit-gnome-authentication-agent-1" "$HOME/.config/sway/config"
test "$(getent passwd polkitd | cut -d: -f3)" -eq 102
test -x /usr/bin/pkexec
test -x /usr/lib/polkit-1/polkitd
test -x /usr/libexec/accounts-daemon
test -x /usr/libexec/polkit-gnome-authentication-agent-1
test -f /etc/pam.d/polkit-1
test -x /usr/sbin/NetworkManager
test -x /usr/bin/nmcli
test -x /usr/sbin/wpa_supplicant
sudo -n nmcli --terse general status | grep -q '^connected:'
for package in bash coreutils networkmanager wpa-supplicant linux-kernel; do
  sudo -n xbpkg verify "$package"
done
if [[ "$EXPECTED_PROFILE" == full ]]; then
  test "$(sudo -n xbpkg owner /usr/bin/curl)" = curl
  for package in curl rsync; do
    sudo -n xbpkg verify "$package"
  done
else
  test "$(sudo -n xbpkg owner /usr/lib/xbee-runtime/libstdc++.so.6.0.34)" = libstdcxx-runtime
  sudo -n xbpkg verify libstdcxx-runtime
  ! sudo -n xbpkg list | awk '{print $1}' | grep -Fxq gcc
  sudo -n ldconfig -p | grep -F '/usr/lib/xbee-runtime/libstdc++.so.6' >/dev/null
  test -x /usr/sbin/alsactl
  for command_name in sway foot waybar pipewire wireplumber alsamixer \
    aplay envy24control hdajackretask hda-verb hdsploader sbiload vxloader; do
    command -v "$command_name" >/dev/null
  done
  for command_name in sfinfo sfconvert; do
    command -v "$command_name" >/dev/null
  done
  command -v dav1d >/dev/null
  command -v faac >/dev/null
  command -v faad >/dev/null
  for package in alsa-utils alsa-tools alsa-firmware audiofile dav1d faac faad2 fdk-aac flac gavl frei0r; do
    sudo -n xbpkg verify "$package"
  done
  test -e /usr/lib/libfdk-aac.so
  faac_test_dir=$(mktemp -d)
  faac_output="$faac_test_dir/Front_Left.mp4"
  faad_output="$faac_test_dir/Front_Left-decoded.wav"
  faac -o "$faac_output" /usr/share/sounds/alsa/Front_Left.wav >/dev/null
  test -s "$faac_output"
  faad -o "$faad_output" "$faac_output" >/dev/null
  test -s "$faad_output"
  file "$faad_output" | grep -Fq "WAVE audio"
  rm -f "$faac_output" "$faad_output"
  rmdir "$faac_test_dir"
  flac_test_dir=$(mktemp -d)
  flac -o "$flac_test_dir/Front_Left.flac" /usr/share/sounds/alsa/Front_Left.wav >/dev/null
  flac -d -o "$flac_test_dir/Front_Left.wav" "$flac_test_dir/Front_Left.flac" >/dev/null
  test -s "$flac_test_dir/Front_Left.wav"
  metaflac --show-total-samples "$flac_test_dir/Front_Left.flac" | grep -Eq '^[1-9][0-9]*$'
  rm -f "$flac_test_dir/Front_Left.flac" "$flac_test_dir/Front_Left.wav"
  rmdir "$flac_test_dir"
  test -e /usr/lib/libgavl.so
  test -d /usr/lib/frei0r-1
  find /usr/lib/frei0r-1 -maxdepth 1 -type f -name '*.so' -print -quit | grep -q .
  gst-inspect-1.0 coreelements >/dev/null
  gst-inspect-1.0 audiotestsrc >/dev/null
  gst-inspect-1.0 flacparse >/dev/null
  gst-inspect-1.0 videoparsersbad >/dev/null
  gst-inspect-1.0 asfdemux >/dev/null
  gst-inspect-1.0 dav1ddec >/dev/null
  gst-inspect-1.0 gtk4paintablesink >/dev/null
  ffmpeg -version | grep -Fq 'ffmpeg version 8.0.1'
  ffprobe -version | grep -Fq 'ffprobe version 8.0.1'
  gst-inspect-1.0 avdec_aac >/dev/null
  for command_name in id3convert id3cp id3info id3tag; do
    command -v "$command_name" >/dev/null
  done
  test -e /usr/lib/libid3.so
  test -e /usr/lib/libigdgmm.so
  test -e /usr/lib/libva.so
  find /usr/lib -name iHD_drv_video.so -print -quit | grep -q .
  find /usr/lib -name i965_drv_video.so -print -quit | grep -q .
  command -v a52dec >/dev/null
  test -e /usr/lib/liba52.so
  test -e /usr/lib/libao.so
  command -v aomdec >/dev/null
  command -v aomenc >/dev/null
  test -e /usr/lib/libaom.so
  test -e /usr/lib/libass.so
  command -v canberra-gtk-play >/dev/null
  test -e /usr/lib/libcanberra-gtk3.so
  command -v cddb_query >/dev/null
  command -v cd-info >/dev/null
  command -v cd-paranoia >/dev/null
  test -e /usr/lib/libcdio.so
  command -v dec265 >/dev/null
  test -e /usr/lib/libde265.so
  test -e /usr/lib/libdvdcss.so
  test -e /usr/lib/libdvdread.so
  test -e /usr/lib/libdvdnav.so
  test -e /usr/lib/libdv.so
  test -e /usr/lib/libmad.so
  command -v mpeg2dec >/dev/null
  test -e /usr/lib/libmusicbrainz5.so
  command -v glad >/dev/null
  test -e /usr/lib/libplacebo.so
  test -e /usr/lib/libsamplerate.so
  command -v vpxenc >/dev/null
  command -v melt >/dev/null
  test -e /usr/lib/libopus.so
  command -v sbcenc >/dev/null
  test -e /usr/lib/libSDL3.so
  test -e /usr/lib/libSDL2.so
  command -v soundstretch >/dev/null
  command -v speexenc >/dev/null
  command -v SvtAv1EncApp >/dev/null
  test -d /usr/include/utf8cpp
  command -v taglib-config >/dev/null
  command -v v4l2-ctl >/dev/null
  test -e /usr/lib/libx264.so
  command -v x265 >/dev/null
  command -v xine-config >/dev/null
  test -x /opt/qt6/bin/qtpaths6
  test -d /usr/share/ECM
  test -d /usr/share/icons/breeze
  test -d /usr/share/plasma-wayland-protocols
  command -v gpg-error >/dev/null
  test -e /usr/lib/libgcrypt.so
  test -e /usr/lib/libical.so
  command -v secret-tool >/dev/null
  command -v mdb_stat >/dev/null
  test -x /opt/qt6/bin/qcatool-qt6
  command -v qrencode >/dev/null
  test -x /opt/kf6/bin/kbuildsycoca6
  test -e /opt/kf6/lib/libKF6CoreAddons.so
  command -v fftw-wisdom >/dev/null
  test -e /usr/lib/libxvidcore.so
  command -v audacious >/dev/null
  command -v cdparanoia >/dev/null
  test -x /opt/kf6/bin/kwave
  command -v lame >/dev/null
  command -v mpg123 >/dev/null
  command -v ogg123 >/dev/null
  command -v mpv >/dev/null
  command -v vlc >/dev/null
  command -v fbxine >/dev/null
  command -v cdrdao >/dev/null
  command -v cdrecord >/dev/null
  command -v growisofs >/dev/null
  command -v cdrskin >/dev/null
  command -v xorriso >/dev/null
  test -e /usr/lib/libisofs.so
  test -e /usr/lib/libnettle.so
  test -e /usr/lib/libtasn1.so
  test -e /usr/lib/libp11-kit.so
  command -v make-ca >/dev/null
  command -v certtool >/dev/null
  test -e /usr/lib/libusb-1.0.so
  test -e /usr/lib/libdaemon.so
  command -v avahi-daemon >/dev/null
  test -e /usr/lib/liblcms2.so
  test -e /usr/lib/libexif.so
  test -e /usr/lib/libwebp.so
  test -e /usr/lib/libopenjp2.so
  command -v pdfinfo >/dev/null
  command -v qpdf >/dev/null
  command -v colormgr >/dev/null
  command -v gusbcmd >/dev/null
  python3 -c 'import lxml'
  command -v itstool >/dev/null
  test -e /usr/lib/libadwaita-1.so
  command -v cupsd >/dev/null
  command -v gs >/dev/null
  command -v cups-genppdupdate >/dev/null
  test -e /usr/lib/libcupsfilters.so
  test -e /usr/lib/libppd.so
  test -x /usr/lib/cups/filter/pdftopdf
  command -v cups-browsed >/dev/null
  command -v scanimage >/dev/null
  command -v simple-scan >/dev/null
  test -e /usr/lib/libgudev-1.0.so
  command -v keyctl >/dev/null
  test -e /usr/lib/libaio.so
  test -e /usr/lib/libpopt.so
  command -v pygmentize >/dev/null
  command -v skdump >/dev/null
  command -v bscalc >/dev/null
  test -e /usr/lib/libnvme.so
  command -v lvm >/dev/null
  command -v cryptsetup >/dev/null
  command -v parted >/dev/null
  test -e /usr/lib/libblockdev.so
  command -v udisksctl >/dev/null
  command -v upower >/dev/null
  test -e /usr/lib/libboost_system.so
  command -v g-ir-scanner >/dev/null
  command -v exiv2 >/dev/null
  test -e /usr/lib/libgexiv2.so
  test -e /usr/lib/libgsf-1.so
  test -e /usr/lib/libhandy-1.so
  test -e /usr/lib/libcloudproviders.so
  command -v exempi >/dev/null
  test -e /usr/lib/libportal.so
  test -e /usr/lib/libgcr-4.so
  test -e /usr/lib/libsoup-3.0.so
  test -e /usr/lib/gvfs/libgvfsdaemon.so
  test -e /usr/lib/libxfce4util.so
  command -v xfconf-query >/dev/null
  test -e /usr/lib/libxfce4ui-2.so
  command -v exo-open >/dev/null
  test -e /usr/lib/libgarcon-1.so
  test -x /usr/lib/tumbler-1/tumblerd
  command -v thunar >/dev/null
  test -e /usr/lib/libyaml.so
  test -e /usr/lib/libfyaml.so
  test -e /usr/lib/libxmlb.so
  command -v appstreamcli >/dev/null
  command -v appstream-util >/dev/null
  test -e /usr/lib/gio/modules/libgiognutls.so
  test -d /usr/share/poppler/cMap
  test -e /usr/lib/libaa.so
  command -v jasper >/dev/null
  test -e /usr/lib/libraw_r.so
  test -e /usr/lib/libbabl-0.1.so
  command -v gegl >/dev/null
  test -e /usr/lib/libmypaint.so
  test -d /usr/share/mypaint-data/1.0/brushes
  command -v magick >/dev/null
  command -v gimp-3.0 >/dev/null
  command -v bluetoothctl >/dev/null
  test -d /usr/lib/python3.14/site-packages/cairo
  test -d /usr/lib/python3.14/site-packages/gi
  command -v blueman-manager >/dev/null
  command -v bt-adapter >/dev/null
  test -e /usr/lib/spa-0.2/bluez5/libspa-bluez5.so
  command -v 7z >/dev/null
  command -v cpio >/dev/null
  command -v unrar >/dev/null
  command -v zip >/dev/null
  command -v rpcgen >/dev/null
  test -e /usr/lib/libtirpc.so
  command -v which >/dev/null
  test -x /usr/libexec/cups-pk-helper-mechanism
  command -v acpid >/dev/null
  command -v at >/dev/null
  command -v automount >/dev/null
  command -v logrotate >/dev/null
  command -v sensors >/dev/null
  command -v lspci >/dev/null
  command -v lsusb >/dev/null
  command -v sg_inq >/dev/null
  command -v powerprofilesctl >/dev/null
  command -v hdparm >/dev/null
  command -v iostat >/dev/null
  command -v fcron >/dev/null
  command -v gpm >/dev/null
  command -v lsb_release >/dev/null
  command -v mc >/dev/null
  command -v mmcli >/dev/null
  test -x /usr/libexec/notification-daemon
  command -v pax >/dev/null
  command -v pm-suspend >/dev/null
  test -e /usr/lib/libuv.so
  test -e /usr/lib/libevent.so
  test -e /usr/lib/libpcap.so
  command -v dig >/dev/null
  command -v nmap >/dev/null
  command -v iwconfig >/dev/null
  command -v rpcbind >/dev/null
  command -v mount.nfs >/dev/null
  test -e /usr/lib/libnsl.so
  command -v kinit >/dev/null
  test -e /usr/lib/libsasl2.so
  command -v ldapsearch >/dev/null
  test -e /usr/lib/libtalloc.so
  command -v smbclient >/dev/null
  command -v mount.cifs >/dev/null
  command -v nft >/dev/null
  command -v iptables >/dev/null
  command -v wg >/dev/null
  command -v openvpn >/dev/null
  command -v ipsec >/dev/null
  command -v ipset >/dev/null
  command -v conntrack >/dev/null
  git --version | grep -Fq 'git version 2.53.0'
for package in gstreamer gst-plugins-base gst-plugins-good gst-plugins-bad gst-plugins-ugly gst-plugins-rs git ffmpeg gst-libav id3lib gmmlib libva intel-media-driver intel-vaapi-driver liba52 libao libaom libass libcanberra libcddb libcdio libde265 libdvdcss libdvdread libdvdnav libdv libmad libmpeg2 neon libmusicbrainz glad vulkan-headers libplacebo libsamplerate libvpx mlt opus sbc sdl3 sdl2-compat soundtouch speex svt-av1 utfcpp taglib v4l-utils x264 x265 xine-lib qt6 extra-cmake-modules breeze-icons plasma-wayland-protocols libgpg-error libgcrypt libical libsecret lmdb qca libqrencode perl-mime-base32 perl-uri kf6-frameworks fftw xvid audacious cdparanoia kwave lame mpg123 vorbis-tools mpv vlc cdrdao cdrtools dvd-rw-tools libburn libisoburn libisofs nettle libtasn1 p11-kit make-ca gnutls libusb libdaemon avahi lcms2 libexif libwebp openjpeg poppler qpdf colord libgusb python-lxml itstool libadwaita cups ghostscript gutenprint libcupsfilters libppd cups-filters cups-browsed sane simple-scan libgudev 7zip cpio unrar zip rpcsvc-proto libtirpc which cups-pk-helper acpid at autofs logrotate lm-sensors pciutils usbutils sg3-utils power-profiles-daemon; do
    sudo -n xbpkg verify "$package"
  done
  test -f /lib/firmware/aica_firmware.bin
  test -f /lib/firmware/cs46xx/ba1
  test -f /lib/firmware/emu/emu1010b.fw
  sway --version | grep -Fq 'sway version'
  foot --version | grep -Fq 'foot version'
  waybar --version | grep -Fq 'Waybar'
  pipewire --version | grep -Fq 'pipewire'
  test -f /usr/share/xdg-desktop-portal/portals/wlr.portal
  test -f /usr/share/xdg-desktop-portal/portals/gtk.portal
fi
test "$(sudo -n find /var/lib/xbpkg/installed -mindepth 1 -maxdepth 1 \
  -type d | wc -l)" -eq "$EXPECTED_PACKAGE_COUNT"
test "$(sudo -n find /var/lib/xbpkg/installed -mindepth 2 -maxdepth 2 \
  -name manifest.yaml -type f | wc -l)" -eq "$EXPECTED_PACKAGE_COUNT"
test "$(sudo -n find /var/lib/xbpkg/installed -mindepth 2 -maxdepth 2 \
  -name files.sha256 -type f | wc -l)" -eq "$EXPECTED_PACKAGE_COUNT"
sudo -n modinfo virtio_blk >/dev/null
sudo -n ip -4 -o address show scope global | grep -q ' inet '
wget -q --timeout=30 -O /dev/null https://example.com/
if [[ "$EXPECTED_PROFILE" == full ]]; then
  curl --fail --silent --show-error --max-time 30 https://example.com/ >/dev/null
  source_file=$(mktemp)
  target_file=$(mktemp)
  printf '%s\n' xbee-package-smoke >"$source_file"
  rsync -a "$source_file" "$target_file"
  cmp "$source_file" "$target_file"
  rm -f "$source_file" "$target_file"
fi
EOF

echo "package-system boot, SSH, systemd, NetworkManager, and $package_count package checks passed"
ssh "${ssh_options[@]}" -q "$admin_user@127.0.0.1" \
  "sudo -n systemctl poweroff" 2>/dev/null || true
for _ in $(seq 1 30); do
  if ! kill -0 "$qemu_pid" 2>/dev/null; then
    qemu_pid=
    echo "package-system smoke test passed ($firmware)"
    exit 0
  fi
  sleep 1
done
echo "guest did not power off cleanly" >&2
exit 1
