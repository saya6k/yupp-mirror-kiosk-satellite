#!/bin/bash
# Builds curl for the mirror's system image: Radxa's Android has none, and
# the Kiosk Satellite installer (common/init/ks-install.sh) fetches the
# release with it. Built with the NDK against bionic, so names resolve
# through Android's resolver (a musl build looks for /etc/resolv.conf, which
# Android has not), with a static OpenSSL. Certificates: Android names its
# cacerts by OpenSSL's old subject hash, which OpenSSL 3 does not look up, so
# the installer's --capath finds nothing; curl also reads a bundle of them,
# /system/etc/security/ca-bundle.pem (patch-images.sh makes it). The NDK runs
# on x86_64 only, so this runs under Rosetta. OpenSSL stays in out/curl/ssl-VERSION.
set -euo pipefail
WORK="${YUPP_WORK:-/Volumes/koa-build/yupp}"
NDK=r27c CURL=8.11.1 OPENSSL=3.0.15 API=30
mkdir -p "$WORK/out/curl" "$WORK/dl"
cat >"$WORK/out/curl/inner.sh" <<IN
set -e
apt-get update -qq >/dev/null && apt-get install -qq -y unzip make perl wget xz-utils file >/dev/null
cd /w/dl
[ -d android-ndk-$NDK ] || { [ -f ndk.zip ] || wget -q -O ndk.zip https://dl.google.com/android/repository/android-ndk-$NDK-linux.zip; unzip -q ndk.zip; }
export ANDROID_NDK_ROOT=/w/dl/android-ndk-$NDK
TC=\$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64
export PATH=\$TC/bin:\$PATH
rm -rf /tmp/b && mkdir /tmp/b && cd /tmp/b
SSL=/w/out/curl/ssl-$OPENSSL
[ -f \$SSL/lib/libssl.a ] || { wget -q https://www.openssl.org/source/openssl-$OPENSSL.tar.gz && tar xf openssl-$OPENSSL.tar.gz
  (cd openssl-$OPENSSL && ./Configure android-arm64 -D__ANDROID_API__=$API no-shared no-tests --prefix=\$SSL --libdir=lib >/dev/null && make -s -j4 >/dev/null 2>&1 && make -s install_sw >/dev/null); }
wget -q https://curl.se/download/curl-$CURL.tar.xz && tar xf curl-$CURL.tar.xz && cd curl-$CURL
CC=aarch64-linux-android$API-clang AR=llvm-ar RANLIB=llvm-ranlib ./configure -q --host=aarch64-linux-android \
    --disable-shared --enable-static --with-openssl=\$SSL --with-ca-bundle=/system/etc/security/ca-bundle.pem --without-ca-path --without-libpsl --without-libidn2 \
    --without-nghttp2 --without-brotli --without-zstd --without-zlib --disable-ldap --disable-manual \
    --disable-docs >/dev/null
make -s -j4 >/dev/null 2>&1
llvm-strip src/curl && cp src/curl /w/out/curl/curl
file /w/out/curl/curl; ls -l /w/out/curl/curl
IN
container run --rm --arch amd64 -c 4 -m 4G --mount type=bind,source="$WORK",target=/w debian:bookworm sh /w/out/curl/inner.sh
