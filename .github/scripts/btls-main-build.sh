#!/usr/bin/env bash
set -euo pipefail
git config --global --add safe.directory /src
git submodule init
git config submodule.external/reference-assemblies.url https://github.com/wine-mono/reference-assemblies.git
git submodule update --init --recursive --depth 1
# Only the 188 declarations are reverted. No engine, runtime, callback or
# unrelated class-library source changes between baseline and fixed builds.
git apply --reverse evidence/declarations.patch
./autogen.sh --prefix=/src/evidence/install --enable-btls --disable-boehm \
  --with-mcs-docs=no --disable-system-aot --without-compiler-server --without-mcs-docs
grep -q '^#define HAVE_BTLS 1' config.h
make -j2
test -s mcs/class/lib/net_4_x-linux/System.dll
mkdir -p evidence/baseline evidence/fixed
cp mcs/class/lib/net_4_x-linux/System.dll evidence/baseline/
git apply evidence/declarations.patch
git diff --exit-code -- mcs/class/System/Mono.Btls
make -j2 -C mcs/class/System HOST_PLATFORM=linux
cp mcs/class/lib/net_4_x-linux/System.dll evidence/fixed/
! cmp -s evidence/baseline/System.dll evidence/fixed/System.dll
sha256sum evidence/{baseline,fixed}/System.dll > evidence/classlib-sha256.txt
./runtime/mono-wrapper --version > evidence/native-runtime-version.txt
find mono/mini -maxdepth 2 -type f -name mono-sgen -exec file {} \; > evidence/native-runtime-files.txt
find mono/btls -type f -name 'libmono-btls-shared.so' -exec sha256sum {} \; > evidence/btls-native-sha256.txt
test -s evidence/btls-native-sha256.txt
git rev-parse HEAD > evidence/build-head.txt
