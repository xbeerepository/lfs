#!/usr/bin/env bash
set -euo pipefail

export LANG=C.UTF-8
export LC_ALL=C.UTF-8
export QT6DIR=/opt/qt6
export KF6_PREFIX=/opt/kf6
export PATH="$QT6DIR/bin:$PATH"
export LD_LIBRARY_PATH="$QT6DIR/lib:$KF6_PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export CMAKE_PREFIX_PATH="$QT6DIR:$KF6_PREFIX"
export PKG_CONFIG_PATH="$QT6DIR/lib/pkgconfig:$KF6_PREFIX/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

install -d "$STAGE$KF6_PREFIX"/{etc,lib,share}
ln -s /etc/dbus-1 "$STAGE$KF6_PREFIX/etc/dbus-1"
ln -s /usr/share/dbus-1 "$STAGE$KF6_PREFIX/share/dbus-1"
ln -s /usr/share/polkit-1 "$STAGE$KF6_PREFIX/share/polkit-1"
ln -s /usr/lib/systemd "$STAGE$KF6_PREFIX/lib/systemd"

while read -r checksum file; do
  [[ -n "${file:-}" ]] || continue
  tar -xf "$SOURCE_DIR/$file" -C "$work_dir"
  package_dir=${file%.tar.xz}
  name=${file%%-6.*}

  if [[ "$name" == kapidox ]]; then
    pushd "$work_dir/$package_dir"
    python3 -m pip wheel -w dist --no-build-isolation --no-deps --no-cache-dir .
    python3 -m pip install --root "$STAGE" --prefix /usr --no-index \
      --find-links dist --no-deps --no-user kapidox
    popd
    rm -rf "$work_dir/$package_dir"
    continue
  fi

  cmake -S "$work_dir/$package_dir" -B "$work_dir/$package_dir/build" \
    -DCMAKE_INSTALL_PREFIX="$KF6_PREFIX" \
    -DCMAKE_INSTALL_LIBEXECDIR=libexec \
    -DCMAKE_PREFIX_PATH="$QT6DIR;$KF6_PREFIX" \
    -DCMAKE_SKIP_INSTALL_RPATH=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_TESTING=OFF \
    -DBUILD_PYTHON_BINDINGS=OFF \
    -DSONNET_NO_BACKENDS=ON \
    -DWITH_X11=OFF \
    -DKWINDOWSYSTEM_X11=OFF \
    -Wno-dev
  cmake --build "$work_dir/$package_dir/build" -j"$JOBS"
  DESTDIR="$STAGE" cmake --install "$work_dir/$package_dir/build"
  # Later frameworks in the same bundle must be able to discover the ones
  # already staged through CMAKE_PREFIX_PATH=/opt/kf6.
  cp -a "$STAGE$KF6_PREFIX/." "$KF6_PREFIX/"
  rm -rf "$work_dir/$package_dir"
done < "$SOURCE_DIR/frameworks.md5"

install -Dm644 /dev/null "$STAGE/etc/ld.so.conf.d/kf6.conf"
printf '%s\n' '/opt/kf6/lib' > "$STAGE/etc/ld.so.conf.d/kf6.conf"
install -Dm644 /dev/null "$STAGE/etc/profile.d/kf6.sh"
printf '%s\n' \
  'KF6_PREFIX=/opt/kf6' \
  'export KF6_PREFIX' \
  'export PATH="$KF6_PREFIX/bin:$PATH"' \
  'export CMAKE_PREFIX_PATH="$KF6_PREFIX${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"' \
  'export PKG_CONFIG_PATH="$KF6_PREFIX/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"' \
  > "$STAGE/etc/profile.d/kf6.sh"

test -x "$STAGE/opt/kf6/bin/kbuildsycoca6"
test -e "$STAGE/opt/kf6/lib/libKF6CoreAddons.so"
