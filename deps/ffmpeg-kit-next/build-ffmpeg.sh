#!/usr/bin/env bash
set -Eeuo pipefail

# Builds the ffmpeg stack in build/ from source:
# FFmpeg + the ffmpeg-kit-next Objective-C wrapper (libffmpegkit),
# compiled for iOS arm64 with the Xcode toolchain on macOS or cross-compiled
# with the Theos toolchain on Linux. TLS comes from the system SecureTransport
# backend, so no OpenSSL is needed.
#
# FFMPEG_TAG must match what the upstream submodule checkout expects
# (scripts/source.sh in the submodule).

MIN_IOS=15.0

FFMPEG_TAG=n8.1.2

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_SRC="$KIT_DIR/upstream/apple/src"
OUT_DIR="$KIT_DIR/build"
BUILD="${BUILD_DIR:-/tmp/nfb-ffmpeg-build}"

if [[ "$(uname)" == "Darwin" ]]; then
    JOBS="$(sysctl -n hw.ncpu)"
    SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
    CC_BIN="$(xcrun --sdk iphoneos -f clang)"
    CXX_BIN="$(xcrun --sdk iphoneos -f clang++)"
    AR_BIN="$(xcrun -f ar)"
    RANLIB_BIN="$(xcrun -f ranlib)"
    NM_BIN="$(xcrun -f nm)"
else
    JOBS="$(nproc)"
    THEOS="${THEOS:-/home/thea/theos}"
    TOOLCHAIN="$THEOS/toolchain/linux/iphone/bin"
    SDK="${SDK:-$(ls -d "$THEOS"/sdks/iPhoneOS*.sdk 2>/dev/null | sort -V | tail -1)}"
    CC_BIN="$TOOLCHAIN/clang"
    CXX_BIN="$TOOLCHAIN/clang++"
    AR_BIN="$TOOLCHAIN/ar"
    RANLIB_BIN="$TOOLCHAIN/ranlib"
    NM_BIN="$TOOLCHAIN/nm"
fi

if [[ "$(uname)" == "Darwin" && "$SDK" != */iPhoneOS*.sdk ]]; then
    cat >&2 <<EOF
iPhoneOS SDK not available: xcrun resolved "$SDK".
Install the full Xcode application and select it with:
  sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
Command Line Tools do not include an iPhoneOS SDK.
EOF
    exit 1
fi

[[ -d "$SDK" ]] || { echo "iPhoneOS SDK not found" >&2; exit 1; }
[[ -f "$KIT_SRC/FFmpegKit.m" ]] || { echo "ffmpeg-kit-next submodule missing; run: git submodule update --init deps/ffmpeg-kit-next/upstream" >&2; exit 1; }

mkdir -p "$BUILD/bin"

# Wrapper compilers so build systems that mangle multi-word CC still work.
cat > "$BUILD/bin/ios-clang" <<EOF
#!/usr/bin/env bash
exec "$CC_BIN" -target arm64-apple-ios$MIN_IOS -isysroot "$SDK" -miphoneos-version-min=$MIN_IOS "\$@"
EOF
cat > "$BUILD/bin/ios-clang++" <<EOF
#!/usr/bin/env bash
exec "$CXX_BIN" -target arm64-apple-ios$MIN_IOS -isysroot "$SDK" -miphoneos-version-min=$MIN_IOS "\$@"
EOF
chmod +x "$BUILD/bin/ios-clang" "$BUILD/bin/ios-clang++"

export PATH="$BUILD/bin:$PATH"

fetch() {
    local url="$1" out="$2"
    [[ -f "$out" ]] || curl -fL --retry 3 -o "$out" "$url"
}

# --- OPENSSL ----------------------------------------------------------------
OPENSSL_SRC="$BUILD/openssl"
OPENSSL_PREFIX="$BUILD/openssl-install"

if [[ ! -f "$OPENSSL_PREFIX/lib/libssl.a" ]]; then
    git clone --depth 1 https://github.com/openssl/openssl.git "$OPENSSL_SRC"

    pushd "$OPENSSL_SRC"

    export IPHONEOS_DEPLOYMENT_TARGET=15.0

    ./Configure ios64-xcrun \
        no-shared \
        no-tests \
        --prefix="$OPENSSL_PREFIX" \
        -mios-version-min=15.0

    make -j"$JOBS"
    make install_sw

    popd
fi

# --- FFmpeg ----------------------------------------------------------------

FFMPEG_SRC="$BUILD/FFmpeg-$FFMPEG_TAG"
FFMPEG_PREFIX="$BUILD/ffmpeg-$FFMPEG_TAG-install"
if [[ ! -f "$FFMPEG_PREFIX/lib/libavcodec.a" ]]; then
    FFMPEG_ARCHIVE="$BUILD/ffmpeg-$FFMPEG_TAG.tar.gz"
    fetch "https://github.com/arthenica/FFmpeg/archive/refs/tags/$FFMPEG_TAG.tar.gz" "$FFMPEG_ARCHIVE"
    rm -rf "$FFMPEG_SRC"
    tar -xzf "$FFMPEG_ARCHIVE" -C "$BUILD"

    pushd "$FFMPEG_SRC" >/dev/null
    # Trimmed to what the media download flows use: probe and demux Twitter
    # HLS/MP4 over HTTPS, decode H.264/HEVC/AAC, scale, encode with the
    # VideoToolbox hardware H.264 encoder or the palette-based GIF pipeline,
    # mux to mp4/gif. Component selection pulls transitive deps (e.g. hls
    # demuxer brings mov/mpegts/aac).
    ./configure \
        --prefix="$FFMPEG_PREFIX" \
        --enable-cross-compile --target-os=darwin --arch=aarch64 --cpu=armv8 \
        --cc=ios-clang --cxx=ios-clang++ --as=ios-clang \
        --ar="$AR_BIN" --ranlib="$RANLIB_BIN" --nm="$NM_BIN" \
        --extra-cflags="-I$OPENSSL_PREFIX/include \
        -Wno-unused-function \
        -Wno-deprecated-declarations \
        -fstrict-aliasing" \
        --extra-ldflags="-L$OPENSSL_PREFIX/lib -Wl,-dead_strip" \
        --extra-libs="-lssl -lcrypto" \
        --disable-shared --enable-static --enable-pthreads --enable-small \
        --disable-programs --disable-doc --disable-debug \
        --disable-zlib --disable-bzlib --disable-iconv \
        --disable-audiotoolbox --disable-avfoundation --disable-coreimage \
        --enable-openssl --enable-videotoolbox \
        --disable-everything \
        --enable-protocol=file,tcp,tls,http,https,crypto,data,udp \
        --enable-demuxer=hls,mpegts,mov,aac \
        --enable-decoder=h264,hevc,aac \
        --enable-parser=h264,hevc,aac \
        --enable-encoder=h264_videotoolbox,gif \
        --enable-muxer=mp4,gif \
        --enable-filter=scale,format,null,anull,split,palettegen,paletteuse \
        --enable-bsf=aac_adtstoasc,extract_extradata
    make -j"$JOBS"
    make install
    # Keep the tree for config.h (the kit build needs it), drop the objects.
    make clean
    popd >/dev/null
fi

# --- libffmpegkit ----------------------------------------------------------

KIT_BUILD="$BUILD/ffmpegkit-obj"
rm -rf "$KIT_BUILD"
mkdir -p "$KIT_BUILD"

KIT_CFLAGS=(
    -I"$KIT_SRC" -I"$FFMPEG_SRC" -I"$FFMPEG_PREFIX/include"
    -DFFMPEG_KIT_ARM64 -DIOS -DFFMPEG_KIT_BUILD_DATE="$(date +%Y%m%d)"
    -Oz -fstrict-aliasing
    -Wno-unused-function -Wno-deprecated-declarations
)

# Source list from apple/src/Makefile.am.
kit_sources=$(sed -n '/^libffmpegkit_la_SOURCES/,/^$/p' "$KIT_SRC/Makefile.am" | grep -oE '[A-Za-z0-9_/]+\.(m|c)')

for src in $kit_sources; do
    obj="$KIT_BUILD/$(echo "$src" | tr '/' '_').o"
    case "$src" in
        *.m) ios-clang -fobjc-arc "${KIT_CFLAGS[@]}" -c "$KIT_SRC/$src" -o "$obj" ;;
        *.c) ios-clang "${KIT_CFLAGS[@]}" -c "$KIT_SRC/$src" -o "$obj" ;;
    esac
done

"$AR_BIN" rcs "$KIT_BUILD/libffmpegkit.a" "$KIT_BUILD"/*.o
"$RANLIB_BIN" "$KIT_BUILD/libffmpegkit.a"

# --- Install ----------------------------------------------------------------

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/lib/pkgconfig"
cp "$KIT_SRC"/*.h "$OUT_DIR/"
cp -r "$FFMPEG_PREFIX"/include/* "$OUT_DIR/"
cp "$FFMPEG_PREFIX"/lib/*.a "$OUT_DIR/lib/"
cp "$OPENSSL_PREFIX"/lib/*.a "$OUT_DIR/lib/"
cp "$KIT_BUILD/libffmpegkit.a" "$OUT_DIR/lib/"
cp "$FFMPEG_PREFIX"/lib/pkgconfig/*.pc "$OUT_DIR/lib/pkgconfig/"

echo "Done. Headers and libraries installed in $OUT_DIR."
