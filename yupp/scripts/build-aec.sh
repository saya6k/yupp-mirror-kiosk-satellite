#!/bin/bash
# Builds aec/yupp_aec_shim.cpp, the mirror's echo canceller, as
# out/aec/libyuppaec.so: 32 bit, like the audio HAL it is preloaded into.
# Upstream builds its shim in the LineageOS tree; here the NDK builds it
# against the same Android 11 sources: WebRTC's and tinyalsa's headers from
# AOSP's android11-release, and, to link with, Radxa's
# libwebrtc_audio_preprocessing.so and the VNDK's libcutils.so, pulled from
# the running mirror (adb). Speex, the pattern removal and the speaker null
# are upstream's files (common/audio/amznaec). The C++ runtime is linked
# statically. The NDK runs on x86_64 only, so this runs under Rosetta.
set -euo pipefail
WORK="${YUPP_WORK:-/Volumes/koa-build/yupp}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
NDK=r27c API=30
O="$WORK/out/aec"
mkdir -p "$O/src/webrtc" "$O/src/tinyalsa" "$O/lib" "$WORK/dl"
G=https://android.googlesource.com/platform/external
[ -d "$O/src/webrtc/webrtc" ] || curl -sfL "$G/webrtc/+archive/refs/heads/android11-release.tar.gz" | tar xz -C "$O/src/webrtc"
[ -d "$O/src/tinyalsa/tinyalsa" ] || curl -sfL "$G/tinyalsa/+archive/refs/heads/android11-release/include.tar.gz" | tar xz -C "$O/src/tinyalsa"
[ -f "$O/lib/libwebrtc_audio_preprocessing.so" ] || adb pull /vendor/lib/libwebrtc_audio_preprocessing.so "$O/lib/"
[ -f "$O/lib/libcutils.so" ] || adb pull /apex/com.android.vndk.v30/lib/libcutils.so "$O/lib/"
rm -rf "$O/yupp" "$O/amznaec"
cp -R "$HERE/aec" "$O/yupp"
cp -R "$HERE/../common/audio/amznaec" "$O/amznaec"
cat >"$O/inner.sh" <<IN
set -e
apt-get update -qq >/dev/null && apt-get install -qq -y unzip file wget >/dev/null
cd /w/dl
# On a case-insensitive disk a few netfilter headers collide; nothing here needs them.
[ -f android-ndk-$NDK/source.properties ] || { [ -f ndk.zip ] || wget -q -O ndk.zip https://dl.google.com/android/repository/android-ndk-$NDK-linux.zip; unzip -qo ndk.zip || true; }
TC=/w/dl/android-ndk-$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin
A=/w/out/aec/amznaec S=\$A/speexdsp/libspeexdsp
cd /w/out/aec
D="-DWEBRTC_POSIX -DWEBRTC_ANDROID -DWEBRTC_LINUX -DFLOATING_POINT -DUSE_KISS_FFT -DEXPORT= -DVAR_ARRAYS"
W="-Wall -Wno-unused-parameter -Wno-unused-variable -Wno-unused-function -Wno-sign-compare -Wno-implicit-fallthrough"
I="-I yupp/compat -I src/webrtc -I src/tinyalsa -I \$A/speexdsp/include -I \$S -I \$A"
rm -rf obj && mkdir obj
for c in mdf preprocess filterbank fftwrap kiss_fft kiss_fftr; do
    \$TC/armv7a-linux-androideabi$API-clang -c -fPIC -O2 \$D \$W \$I \$S/\$c.c -o obj/\$c.o
done
\$TC/armv7a-linux-androideabi$API-clang++ -shared -fPIC -O2 -std=c++17 \$D \$W \
    -Wno-deprecated-declarations -Wno-vla-cxx-extension \$I \
    yupp/yupp_aec_shim.cpp \$A/mic_pattern.cpp \$A/speaker_null.cpp obj/*.o \
    -L lib -lwebrtc_audio_preprocessing -lcutils -llog -ldl -lm -static-libstdc++ \
    -Wl,--no-undefined -o libyuppaec.so
\$TC/llvm-strip libyuppaec.so
file libyuppaec.so; ls -l libyuppaec.so
IN
container run --rm --arch amd64 -c 4 -m 4G --mount type=bind,source="$WORK",target=/w debian:bookworm sh /w/out/aec/inner.sh
