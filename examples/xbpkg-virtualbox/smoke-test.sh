#!/usr/bin/env bash
set -euo pipefail

repository_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
source_example_dir="$repository_root/examples/xbpkg-virtualbox"
xbee_source=${XBEE_SOURCE:-"$(dirname "$repository_root")/xbee-intern"}
virtualbox_source=${XBEE_VIRTUALBOX_SOURCE:-"$(dirname "$repository_root")/xbee-virtualbox"}
cache_root=${XBEE_LFS_CACHE_ROOT:-"$HOME/.xbee/cache-exports"}
build_system=${XBEE_LFS_BUILD_SYSTEM:-build-system-13.0-main-041201c752}
cache_dir="$cache_root/$build_system"
minimal_archive=${XBEE_LFS_MINIMAL_ARCHIVE:-"$cache_dir/package-minimal-system-0.1.1-main-041201c752.tar"}
repository_archive=${XBEE_LFS_REPOSITORY_ARCHIVE:-"$cache_dir/package-repository-0.34.1-main-041201c752.tar"}
http_port=18081
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/xbee-lfs-xbpkg-vbox.XXXXXX")
example_dir="$work_dir/example"
http_pid=
environment_touched=false

cleanup() {
  local status=$?
  if [[ "$status" -ne 0 && "${XBEE_LFS_PRESERVE_FAILURE:-false}" == true ]]; then
    echo "preserving failed environment and diagnostics in $work_dir" >&2
    trap - EXIT INT TERM
    exit "$status"
  fi
  if "$environment_touched"; then
    (cd "$example_dir" && "$work_dir/xbee" delete --force) || true
  fi
  if [[ -n "$http_pid" ]] && kill -0 "$http_pid" 2>/dev/null; then
    kill "$http_pid" 2>/dev/null || true
    wait "$http_pid" 2>/dev/null || true
  fi
  case "$work_dir" in
    "${TMPDIR:-/tmp}"/xbee-lfs-xbpkg-vbox.*)
      [[ ! -d "$work_dir" ]] || find "$work_dir" -depth -delete
      ;;
    *) echo "refusing unexpected cleanup path: $work_dir" >&2 ;;
  esac
  exit "$status"
}
trap cleanup EXIT INT TERM

for command_name in VBoxManage go gzip ip python3 tar timeout; do
  command -v "$command_name" >/dev/null ||
    { echo "required command not found: $command_name" >&2; exit 1; }
done
[[ -f "$xbee_source/go.mod" ]] ||
  { echo "XBee source tree not found: $xbee_source" >&2; exit 1; }
[[ -f "$virtualbox_source/go.mod" ]] ||
  { echo "VirtualBox provider source tree not found: $virtualbox_source" >&2; exit 1; }
for archive in "$minimal_archive" "$repository_archive"; do
  [[ -f "$archive" ]] || { echo "builder artefact not found: $archive" >&2; exit 1; }
done
if timeout 1 bash -c "</dev/tcp/127.0.0.1/$http_port" 2>/dev/null; then
  echo "host TCP port is already in use: $http_port" >&2
  exit 1
fi

mkdir "$work_dir/http"
cp -a "$source_example_dir" "$example_dir"
repository_host=$(
  ip -4 route get 1.1.1.1 |
    awk '{for (i = 1; i <= NF; i++) if ($i == "src") {print $(i + 1); exit}}'
)
[[ -n "$repository_host" ]] ||
  { echo "cannot determine the host IPv4 address" >&2; exit 1; }
sed -i "s/XBEE_REPOSITORY_HOST/$repository_host/g" \
  "$example_dir/pack/xbee-pack.yaml"
(
  cd "$xbee_source"
  go build -o "$work_dir/xbee" ./xbee/main
)
(
  cd "$virtualbox_source"
  go build -o "$work_dir/xbee-virtualbox" ./main
)
gzip -c "$work_dir/xbee-virtualbox" >"$work_dir/http/xbee-virtualbox.gz"
export PATH="$work_dir:$PATH"
export XBEE_GUEST_BINARY="$work_dir/xbee"
export XBEE_PROVIDER_BINARY_URL="http://127.0.0.1:18081/xbee-virtualbox.gz"
tar -xf "$minimal_archive" -C "$work_dir"
tar -xf "$repository_archive" -C "$work_dir"
cp "$work_dir/opt/xbee-lfs-native/xbee-lfs-native-13.0-x86_64-minimal-virtualbox.vmdk" \
  "$work_dir/http/xbee-lfs-minimal.vmdk"
mv "$work_dir/opt/xbee-lfs-repository" "$work_dir/http/repository"
python3 -m http.server "$http_port" --bind 0.0.0.0 \
  --directory "$work_dir/http" >"$work_dir/http.log" 2>&1 &
http_pid=$!
server_ready=false
for _ in $(seq 1 50); do
  if timeout 1 bash -c "</dev/tcp/127.0.0.1/$http_port" 2>/dev/null; then
    server_ready=true
    break
  fi
  sleep 0.1
done
[[ "$server_ready" == true ]] ||
  { echo "local HTTP server did not become ready" >&2; exit 1; }

# The provider cache is keyed by URL, while this local URL intentionally stays
# stable across rebuilt images.
cached_vmdk="$HOME/.xbee/cache-artefacts/127.0.0.1:18081/xbee-lfs-minimal.vmdk"
[[ ! -f "$cached_vmdk" ]] || unlink "$cached_vmdk"
cached_provider="$HOME/.xbee/cache-artefacts/127.0.0.1:18081/xbee-virtualbox.gz"
[[ ! -f "$cached_provider" ]] || unlink "$cached_provider"
cached_provider_executable=${cached_provider%.gz}
[[ ! -f "$cached_provider_executable" ]] || unlink "$cached_provider_executable"

cd "$example_dir"
"$work_dir/xbee" validate
"$work_dir/xbee" show model >/dev/null
"$work_dir/xbee" admin delete pack --host lfs --force >/dev/null 2>&1 || true
"$work_dir/xbee" pack
if [[ "${XBEE_LFS_TEST_LIFECYCLE:-true}" == true ]]; then
  environment_touched=true
  "$work_dir/xbee" up
  printf '%s\n' \
    'test -x /usr/bin/curl' \
    'xbpkg verify curl' \
    'test "$(xbpkg owner /usr/bin/curl)" = curl' \
    'test "$(xbpkg list | wc -l)" -eq 45' \
    'exit' |
    "$work_dir/xbee" enter
  "$work_dir/xbee" delete --force
  environment_touched=false
fi
echo "XBee gpg/repo/pkg integration on minimal LFS passed"
