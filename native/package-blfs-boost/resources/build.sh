#!/usr/bin/env bash
set -euo pipefail
./bootstrap.sh --prefix=/usr --with-python=python3
./b2 stage -j"$JOBS" threading=multi link=shared --without-mpi --without-graph_parallel
./b2 install --prefix="$STAGE/usr" threading=multi link=shared --without-mpi --without-graph_parallel
test -e "$STAGE/usr/include/boost/system/error_code.hpp"
test -e "$STAGE/usr/lib/libboost_filesystem.so"
