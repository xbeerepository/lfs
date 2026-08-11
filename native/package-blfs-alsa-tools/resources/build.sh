#!/usr/bin/env bash
set -euo pipefail

# BLFS excludes the obsolete Qt/GTK2 tools. The HDSP frontends additionally
# require FLTK, which is not part of the current Wayland desktop profile.
rm -rf qlo10k1 echomixer rmedigicontrol hdspconf hdspmixer Makefile gitcompile

for tool in *; do
  case "$tool" in
    seq) tool_dir=seq/sbiload ;;
    *)   tool_dir=$tool ;;
  esac

  pushd "$tool_dir"
  ./configure --prefix=/usr
  make -j"$JOBS"
  make DESTDIR="$STAGE" install
  popd
done
