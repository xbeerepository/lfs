#!/usr/bin/env bash
set -euo pipefail
for precision in double float long-double; do
  make distclean >/dev/null 2>&1 || true
  extra=(); [[ "$precision" == float ]] && extra+=(--enable-float); [[ "$precision" == long-double ]] && extra+=(--enable-long-double)
  simd=(); [[ "$precision" != long-double ]] && simd+=(--enable-sse2 --enable-avx --enable-avx2)
  ./configure --prefix=/usr --enable-shared --disable-static --enable-threads "${simd[@]}" "${extra[@]}"
  make -j"$JOBS"
  make DESTDIR="$STAGE" install
done
test -e "$STAGE/usr/lib/libfftw3l.so"
