#!/usr/bin/env bash
set -euo pipefail

MIN_FREE_GIB=${MIN_FREE_GIB:-15}
MIN_FREE_PERCENT=${MIN_FREE_PERCENT:-4}
CHECK_INTERVAL_SECONDS=${CHECK_INTERVAL_SECONDS:-10}
BUILD_SELECTOR=${1:-.}

build_pid=$$
monitor_pid=

stop_monitor() {
  if [[ -n "${monitor_pid}" ]]; then
    kill "${monitor_pid}" 2>/dev/null || true
    wait "${monitor_pid}" 2>/dev/null || true
  fi
}

monitor_disk() {
  while kill -0 "${build_pid}" 2>/dev/null; do
    read -r blocks available < <(df -Pk / | awk 'NR == 2 { print $2, $4 }')
    free_gib=$((available / 1024 / 1024))
    free_percent=$((available * 100 / blocks))

    printf '[disk-guard] free=%s GiB (%s%%), limits=%s GiB/%s%%\n' \
      "${free_gib}" "${free_percent}" "${MIN_FREE_GIB}" "${MIN_FREE_PERCENT}"

    if (( free_gib < MIN_FREE_GIB || free_percent < MIN_FREE_PERCENT )); then
      printf '[disk-guard] safety threshold reached; stopping XBee build\n' >&2
      kill -TERM "${build_pid}" 2>/dev/null || true
      return 75
    fi

    sleep "${CHECK_INTERVAL_SECONDS}"
  done
}

trap stop_monitor EXIT
monitor_disk &
monitor_pid=$!

xbee builder build "${BUILD_SELECTOR}"
