#!/usr/bin/env bash
set -euo pipefail
sed -i -e '/AM_PATH_AALIB,/s/AM_PATH_AALIB/[&]/' aalib.m4
sed 's/stdscr->_max\([xy]\) + 1/getmax\1(stdscr)/' -i src/aacurses.c
sed -i '1i#include <stdlib.h>' src/aa{fire,info,lib,linuxkbd,savefont,test,regist}.c
sed -i '1i#include <string.h>' src/aa{kbdreg,moureg,test,regist}.c
sed -i '/rawmode_init/,/^}/s/return;/return 0;/' src/aalinuxkbd.c
autoconf
./configure --prefix=/usr --infodir=/usr/share/info --mandir=/usr/share/man --with-ncurses=/usr --disable-static --without-x
make -j"$JOBS"
make DESTDIR="$STAGE" install
test -e "$STAGE/usr/lib/libaa.so"
