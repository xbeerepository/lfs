#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 7 ]]; then
  echo "usage: build-blfs-xbpkg.sh PACKAGE_NAME PACKAGE_VERSION SOURCE_NAME RUNTIME_DEPS JOBS SRC OUT" >&2
  exit 2
fi

package_name=$1
package_version=$2
source_name=$3
runtime_dependencies=$4
jobs=$5
source_root=$6
output_root=$7

if [[ ! "$package_name" =~ ^[a-z0-9][a-z0-9+._-]*$ ||
      ! "$package_version" =~ ^[A-Za-z0-9][A-Za-z0-9+._~-]*$ ]]; then
  echo "invalid package identity: $package_name $package_version" >&2
  exit 2
fi

case "$jobs" in
  ''|*[!0-9]*|0)
    echo "lfs.jobs must be a positive integer" >&2
    exit 2
    ;;
esac

if [[ "$runtime_dependencies" != "null" ]]; then
  # xbpkg metadata consumer expects space-separated package names
  xbpkg_deps="$runtime_dependencies"
else
  xbpkg_deps=""
fi

build_dir="$source_root/package-build/$package_name"
source_archive="$source_root/$source_name"
work_root="$source_root/package-$package_name"
output_dir="$output_root/opt/xbee-lfs-packages"

mkdir -p "$work_root" "$output_dir"

if [[ ! -f "$source_archive" ]]; then
  echo "required source archive not found: $source_archive" >&2
  echo "add this file in final-sources/resources/sources.tsv before building BLFS packages." >&2
  exit 1
fi

cat >"$output_root/opt/xbee-lfs-native-build-flag.txt" <<EOF
package-name: $package_name
package-version: $package_version
source-name: $source_name
runtime-dependencies: ${xbpkg_deps:-<empty>}
jobs: $jobs
source-root: $source_root
output-root: $output_root
EOF

cat <<'EOF'
Cette étape attend un script BLFS concret dans ce template.
Copie-colle un bloc d'actions chroot + installation dans ce fichier puis
remplace le contenu ci-dessus en conséquence :

- décompresser la source
- chroot dans le rootfs final
- exécuter ./configure/make/make install vers /stage
- créer les manifestes xbpkg (même logique que build-xbpkg.sh)

Pour l'instant ce squelette stoppe volontairement ici.
EOF
exit 1
