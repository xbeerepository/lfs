#!/usr/bin/env bash
set -euo pipefail

patch -Np1 -i /sources/ffmpeg-8.0.1-chromium_method-1.patch
sed -e '/adaptive/c\ param->aq_mode = 0;' -i libavcodec/libsvtav1.c
sed -i '/#include "ffplay_renderer.h"/a #include <libplacebo/config.h>' \
  fftools/ffplay_renderer.c
sed -i 's/SDL_VERSION_ATLEAST(2, 0, 6) && CONFIG_LIBPLACEBO/SDL_VERSION_ATLEAST(2, 0, 6) \&\& CONFIG_LIBPLACEBO \&\& defined(PL_HAVE_VULKAN)/' \
  fftools/ffplay_renderer.c

./configure \
  --prefix=/usr \
  --enable-gpl \
  --enable-version3 \
  --enable-nonfree \
  --disable-static \
  --enable-shared \
  --disable-debug \
  --enable-libdav1d \
  --enable-libaom \
  --enable-libass \
  --enable-libplacebo \
  --enable-libvpx \
  --enable-libmp3lame \
  --enable-libopus \
  --enable-libsvtav1 \
  --enable-libx264 \
  --enable-libx265 \
  --enable-libspeex \
  --enable-libxvid \
  --enable-libfdk-aac \
  --enable-libfreetype \
  --enable-libvorbis \
  --enable-openssl \
  --enable-libfontconfig \
  --enable-libfribidi \
  --enable-frei0r \
  --enable-libdrm \
  --enable-vaapi \
  --enable-libpulse \
  --docdir=/usr/share/doc/ffmpeg-8.0.1
make -j"$JOBS"
gcc tools/qt-faststart.c -o tools/qt-faststart

make DESTDIR="$STAGE" install
install -Dm755 tools/qt-faststart "$STAGE/usr/bin/qt-faststart"
install -d "$STAGE/usr/share/doc/ffmpeg-8.0.1"
install -m644 doc/*.txt "$STAGE/usr/share/doc/ffmpeg-8.0.1/"
